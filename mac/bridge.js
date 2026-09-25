import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import https from 'node:https';
import http from 'node:http';
import crypto from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import WebSocket, {WebSocketServer} from 'ws';
import selfsigned from 'selfsigned';
import {SessionLog} from './session-log.js';
import {CodexClient} from './codex-client.js';
import {defaultModules, normalizeModules} from './modules.js';
import {defaultAppearance, normalizeAppearance} from './appearance.js';

const directory = path.dirname(fileURLToPath(import.meta.url));
const project = path.dirname(directory);
const dataDir = process.env.PASSPORT_DATA_DIR || path.join(project, '.data');
const port = Number(process.env.PASSPORT_PORT || 3219);
fs.mkdirSync(dataDir, {recursive: true, mode: 0o700});
const tokenFile = path.join(dataDir, 'bridge-token');
if (!fs.existsSync(tokenFile)) fs.writeFileSync(tokenFile, crypto.randomBytes(32).toString('base64url'), {mode: 0o600, flag: 'wx'});
const token = fs.readFileSync(tokenFile, 'utf8').trim();
if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error('Invalid bridge token; delete .data/bridge-token and pair again');
const appearanceFile = path.join(dataDir, 'appearance.json');
const customCharacterFile = path.join(dataDir, 'custom-character.png');
const modulesFile = path.join(dataDir, 'modules.json');
let modules = defaultModules;
try { modules = normalizeModules(JSON.parse(fs.readFileSync(modulesFile, 'utf8'))); } catch {}
let appearance = defaultAppearance;
try {
  const saved = JSON.parse(fs.readFileSync(appearanceFile, 'utf8'));
  if (saved.theme === 'apple-pie') appearance = {...defaultAppearance, theme: 'custom', character: 'custom'};
  else appearance = normalizeAppearance(saved);
} catch {}
let pairingCode = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
let bluetoothReady = false;
const keyFile = path.join(dataDir, 'server.key');
const certFile = path.join(dataDir, 'server.crt');
if (!fs.existsSync(keyFile) || !fs.existsSync(certFile)) {
  const result = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-nodes',
    '-keyout', keyFile, '-out', certFile, '-days', '365', '-subj', '/CN=Redmi AI Passport'], {stdio: 'ignore'});
  if (result.status !== 0) {
    const generated = await selfsigned.generate([{name: 'commonName', value: 'AI Passport'}],
      {days: 365, keySize: 2048, algorithm: 'sha256'});
    fs.writeFileSync(keyFile, generated.private, {mode: 0o600});
    fs.writeFileSync(certFile, generated.cert, {mode: 0o600});
  }
  fs.chmodSync(keyFile, 0o600);
}
const certificate = fs.readFileSync(certFile);
const fingerprint = crypto.createHash('sha256').update(new crypto.X509Certificate(certificate).raw).digest('hex');
const interfaces = os.networkInterfaces();
const network = [...(interfaces.en0 || []), ...Object.entries(interfaces).filter(([name]) => !name.startsWith('utun') && name !== 'en0').flatMap(([, addresses]) => addresses)]
  .find(x => x && x.family === 'IPv4' && !x.internal && !x.address.startsWith('169.254.'));
const host = process.env.PASSPORT_HOST || network?.address;
if (!host) throw new Error('No LAN IPv4 address found. Connect the computer to a network or use USB mode.');
const logs = new SessionLog();
const codex = new CodexClient();
let official = new Map();
let officialLastOK = 0;

function tasks() {
  return logs.snapshot().map(task => {
    const info = official.get(task.id);
    const status = info?.status?.type === 'active' ? 'working' : task.status;
    return {id: task.id, project: task.project, title: info?.name || task.project,
      status, updatedAt: task.updatedAt, summary: task.summary || '', updates: task.updates || [], source: task.source};
  });
}

function send(ws, value) { if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(value)); }
function broadcast(value) { for (const ws of wss.clients) send(ws, value); }
function run(binary, args, timeoutMs) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, {stdio: ['ignore', 'pipe', 'pipe']});
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error(`${binary} timed out`)); }, timeoutMs);
    child.stdout.on('data', data => { output += data; });
    child.stderr.on('data', data => { errors += data; });
    child.on('error', error => { clearTimeout(timer); reject(error); });
    child.on('close', code => {
      clearTimeout(timer);
      if (code === 0) resolve(output);
      else reject(new Error(`${binary} failed: ${errors.slice(-240)}`));
    });
  });
}

const server = https.createServer({key: fs.readFileSync(keyFile), cert: certificate}, (req, res) => {
  const url = new URL(req.url, 'https://localhost');
  if (req.method === 'GET' && url.pathname === '/character' && url.searchParams.get('token') === token) {
    const file = appearance.character === 'custom' && fs.existsSync(customCharacterFile)
      ? customCharacterFile : path.join(project, 'android/app/src/main/res/drawable-nodpi/companion.png');
    res.writeHead(200, {'Content-Type': 'image/png', 'Cache-Control': 'no-store'});
    fs.createReadStream(file).pipe(res); return;
  }
  res.writeHead(404); res.end();
});
const wss = new WebSocketServer({noServer: true, maxPayload: 8 * 1024 * 1024});
function snapshot(ws) { send(ws, {type: 'snapshot', tasks: tasks(), theme: appearance.theme, appearance, modules, serverTime: Date.now(), officialConnected: codex.ready}); }
server.on('upgrade', (req, socket, head) => {
  const provided = new URL(req.url, 'https://localhost').searchParams.get('token') || '';
  const a = Buffer.from(provided); const b = Buffer.from(token);
  if (a.length !== b.length || !crypto.timingSafeEqual(a,b)) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, ws => wss.emit('connection', ws));
});

async function transcribe(base64, requestId, ws) {
  const bytes = Buffer.from(base64 || '', 'base64');
  if (!bytes.length || bytes.length > 6 * 1024 * 1024) throw new Error('Audio must be 1 byte to 6 MB');
  const input = path.join(dataDir, `${crypto.randomUUID()}.m4a`);
  const wav = input.replace('.m4a', '.wav');
  fs.writeFileSync(input, bytes, {mode: 0o600});
  try {
    await run('ffmpeg', ['-nostdin', '-loglevel', 'error', '-y', '-i', input, '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', wav], 15000);
    const whisper = process.env.WHISPER_CLI || 'whisper-cli';
    const model = process.env.WHISPER_MODEL || path.join(dataDir, 'ggml-base.bin');
    if (!fs.existsSync(model)) throw new Error(`Missing local transcription model: ${model}`);
    const output = await run(whisper, ['-m', model, '-f', wav, '-l', 'auto', '-nt', '-np', '-otxt'], 120000);
    const transcript = fs.existsSync(`${wav}.txt`) ? fs.readFileSync(`${wav}.txt`, 'utf8').trim() : output.trim();
    send(ws, {type: 'transcript', requestId, text: transcript.replace(/^\[BLANK_AUDIO\]$/i, '')});
  } finally {
    for (const file of [input, wav, `${wav}.txt`]) try { fs.unlinkSync(file); } catch {}
  }
}

wss.on('connection', ws => {
  snapshot(ws);
  ws.on('message', async raw => {
    let message;
    try { message = JSON.parse(String(raw)); } catch { send(ws, {type: 'error', message: 'Invalid message'}); return; }
    try {
      if (message.type === 'audio') await transcribe(message.data, message.requestId, ws);
      else if (message.type === 'command') {
        const prompt = String(message.text || '').trim();
        const target = message.threadId ? tasks().find(x => x.id === message.threadId) : null;
        if (message.threadId && !target) throw new Error('Task not found in local sessions');
        if (target?.status === 'working') throw new Error('Task is still running');
        const id = await codex.command(prompt, message.threadId || null, project);
        send(ws, {type: 'command_result', requestId: message.requestId, threadId: id});
      } else if (message.type === 'refresh') {
        snapshot(ws);
      }
    } catch (error) { send(ws, {type: 'error', requestId: message.requestId, message: error.message}); }
  });
});

server.listen(port, '0.0.0.0', () => console.log(`Secure bridge on ${host}:${port}`));

// The desktop manager connects only over loopback and authenticates with the existing bridge token.
const control = http.createServer((req, res) => {
  const provided = Buffer.from((req.headers.authorization || '').replace(/^Bearer /, ''));
  const expected = Buffer.from(token);
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
    res.writeHead(401); res.end(); return;
  }
  const reply = (status, value) => {
    res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8'});
    res.end(JSON.stringify(value));
  };
  if (req.method === 'GET' && req.url === '/status') {
    reply(200, {pairingCode, bluetoothReady, connected: wss.clients.size > 0, clients: wss.clients.size,
      theme: appearance.theme, appearance, modules, taskCount: tasks().length, codexConnected: codex.ready, host, port});
  } else if (req.method === 'POST' && (req.url === '/theme' || req.url === '/appearance')) {
    let body = '';
    req.on('data', chunk => { body += chunk; if (body.length > 12 * 1024 * 1024) req.destroy(); });
    req.on('end', () => {
      try {
        const value = JSON.parse(body);
        if (req.url === '/theme') value.theme = value.theme === 'midnight' ? 'midnight' : 'ocean';
        const image = value.imageBase64;
        delete value.imageBase64;
        if (image !== undefined) {
          const bytes = Buffer.from(String(image), 'base64');
          if (bytes.length < 64 || bytes.length > 8 * 1024 * 1024 || bytes.subarray(1, 4).toString() !== 'PNG')
            throw new Error('Character image must be a PNG smaller than 8 MB');
          fs.writeFileSync(customCharacterFile, bytes, {mode: 0o600});
          value.character = 'custom'; value.revision = Date.now();
        }
        appearance = normalizeAppearance(value);
        if (appearance.character === 'custom' && !fs.existsSync(customCharacterFile)) throw new Error('Choose a character PNG first');
        fs.writeFileSync(appearanceFile, JSON.stringify(appearance), {mode: 0o600});
        broadcast({type: 'appearance', theme: appearance.theme, appearance});
        reply(200, appearance);
      } catch (error) { reply(400, {error: error.message}); }
    });
  } else if (req.method === 'POST' && req.url === '/modules') {
    let body = '';
    req.on('data', chunk => { body += chunk; if (body.length > 8192) req.destroy(); });
    req.on('end', () => {
      let next;
      try { next = normalizeModules(JSON.parse(body)); }
      catch (error) { reply(400, {error: error.message}); return; }
      modules = next;
      fs.writeFileSync(modulesFile, JSON.stringify(modules), {mode: 0o600});
      broadcast({type: 'modules', modules});
      reply(200, modules);
    });
  } else if (req.method === 'POST' && req.url === '/stop') {
    reply(200, {stopping: true});
    setImmediate(() => process.kill(process.pid, 'SIGINT'));
  } else reply(404, {error: 'Not found'});
});
control.listen(3220, '127.0.0.1');

// USB-only bootstrap. adb reverse exposes this loopback port to the phone without opening it to the LAN.
const pairing = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method !== 'GET' || url.pathname !== '/pair' || url.searchParams.get('code') !== pairingCode) {
    res.writeHead(403); res.end(); return;
  }
  res.writeHead(200, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
  res.end(JSON.stringify({endpoint: `${host}:${port}:${token}`, fingerprint}));
});
pairing.listen(3221, '127.0.0.1');

async function refresh() {
  if (codex.ready && Date.now() - officialLastOK > 10000) {
    try {
      official = new Map((await codex.list()).map(t => [t.id, t]));
      officialLastOK = Date.now();
    } catch (error) { console.warn('App Server list:', error.message); officialLastOK = Date.now(); }
  }
  broadcast({type: 'snapshot', tasks: tasks(), theme: appearance.theme, appearance, modules, serverTime: Date.now(), officialConnected: codex.ready});
}
setInterval(refresh, 2000).unref();
codex.on('notification', refresh);
codex.on('warning', message => { if (message) console.warn('Codex:', message); });
codex.start().then(async () => {
  console.log('Codex App Server connected');
  try { const list = await codex.list(); official = new Map(list.map(t => [t.id, t])); console.log(`App Server sees ${list.length} local tasks`); }
  catch (error) { console.warn('App Server task listing failed:', error.message); }
}).catch(error => console.warn('Codex App Server unavailable:', error.message));

if (!process.env.PASSPORT_NO_BLE) {
  const binary = process.env.PASSPORT_BLE_BIN || path.join(directory, 'bin', 'passport-ble');
  if (!process.env.PASSPORT_BLE_BIN) fs.mkdirSync(path.dirname(binary), {recursive: true});
  const source = path.join(directory, 'ble.swift');
  if (!process.env.PASSPORT_BLE_BIN && (!fs.existsSync(binary) || fs.statSync(binary).mtimeMs < fs.statSync(source).mtimeMs)) {
    const result = spawnSync('swiftc', ['-O', source, '-o', binary, '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__info_plist', '-Xlinker', path.join(directory, 'ble-info.plist')], {encoding: 'utf8'});
    if (result.status !== 0) console.warn('Bluetooth helper compile failed:', result.stderr);
  }
  if (fs.existsSync(binary)) {
    const ble = spawn(binary, [host, String(port), token, fingerprint, pairingCode]);
    ble.stderr.on('data', data => {
      const message = String(data);
      if (message.includes('Bluetooth ready')) bluetoothReady = true;
      process.stderr.write(data);
    });
    ble.on('exit', code => { bluetoothReady = false; console.warn('Bluetooth helper stopped:', code); });
    process.on('SIGINT', () => ble.kill());
  }
}
process.on('SIGINT', () => { codex.stop(); pairing.close(); control.close(); server.close(); process.exit(0); });

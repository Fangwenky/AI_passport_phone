import {spawn} from 'node:child_process';
import {EventEmitter} from 'node:events';

export class CodexClient extends EventEmitter {
  constructor() { super(); this.sequence = 0; this.pending = new Map(); this.ready = false; }
  async start() {
    this.child = spawn('codex', ['app-server', '--stdio'], {stdio: ['pipe', 'pipe', 'pipe']});
    this.child.stdout.setEncoding('utf8');
    let buffer = '';
    this.child.stdout.on('data', chunk => {
      buffer += chunk;
      let newline;
      while ((newline = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, newline); buffer = buffer.slice(newline + 1);
        try { this.receive(JSON.parse(line)); } catch { this.emit('warning', 'Codex returned malformed JSON'); }
      }
    });
    this.child.stderr.on('data', data => this.emit('warning', String(data).trim()));
    this.child.on('exit', () => {
      this.ready = false;
      for (const {reject, timer} of this.pending.values()) { clearTimeout(timer); reject(new Error('Codex app-server stopped')); }
      this.pending.clear();
      this.emit('closed');
    });
    await this.request('initialize', {clientInfo: {name: 'redmi_ai_passport', title: 'Redmi AI Passport', version: '0.1.0'}});
    this.send({method: 'initialized'});
    this.ready = true;
  }
  send(message) { this.child.stdin.write(JSON.stringify(message) + '\n'); }
  request(method, params = {}, timeoutMs = 15000) {
    if (!this.child || this.child.exitCode !== null) return Promise.reject(new Error('Codex app-server unavailable'));
    const id = ++this.sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`${method} timed out`)); }, timeoutMs);
      this.pending.set(id, {resolve, reject, timer});
      this.send({id, method, params});
    });
  }
  receive(message) {
    if (message.id !== undefined) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id); clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message || JSON.stringify(message.error)));
      else pending.resolve(message.result);
      return;
    }
    if (message.method) this.emit('notification', message);
  }
  async list() {
    const result = await this.request('thread/list', {limit: 50, sortKey: 'updated_at', sourceKinds: ['cli', 'vscode', 'appServer', 'unknown']});
    return result.data || [];
  }
  async command(prompt, threadId, cwd) {
    if (!prompt || prompt.length > 4000) throw new Error('Command must contain 1–4000 characters');
    if (threadId) {
      const data = await this.request('thread/read', {threadId, includeTurns: false});
      if (data.thread?.status?.type === 'active') throw new Error('This task is running; wait until it is idle');
      await this.request('thread/resume', {threadId});
    } else {
      const data = await this.request('thread/start', cwd ? {cwd} : {});
      threadId = data.thread.id;
    }
    await this.request('turn/start', {threadId, input: [{type: 'text', text: prompt}]});
    return threadId;
  }
  stop() { this.child?.kill(); }
}

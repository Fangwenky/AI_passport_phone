const {app, BrowserWindow, dialog, ipcMain} = require('electron');
const {spawn, spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

let window;
let bridge;
const dataDir = () => path.join(app.getPath('userData'), 'data');
const bridgeRoot = () => app.isPackaged ? path.join(process.resourcesPath, 'bridge') : path.join(__dirname, '..');
const token = () => fs.readFileSync(path.join(dataDir(), 'bridge-token'), 'utf8').trim();

function adbPath() {
  const bundled = path.join(process.resourcesPath, 'platform-tools', 'adb.exe');
  if (app.isPackaged && fs.existsSync(bundled)) return bundled;
  const found = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['adb'], {encoding: 'utf8'});
  return found.status === 0 ? found.stdout.trim().split(/\r?\n/)[0] : null;
}
function reverseUsb() {
  const adb = adbPath();
  if (!adb) return false;
  return [3219, 3221].every(port => spawnSync(adb, ['reverse', `tcp:${port}`, `tcp:${port}`]).status === 0);
}
async function api(route, method='GET', value) {
  const response = await fetch(`http://127.0.0.1:3220${route}`, {
    method, headers: {'Authorization': `Bearer ${token()}`, ...(value ? {'Content-Type':'application/json'} : {})},
    body: value ? JSON.stringify(value) : undefined, signal: AbortSignal.timeout(3500)
  });
  if (!response.ok) throw new Error((await response.json().catch(()=>({}))).error || `HTTP ${response.status}`);
  return response.json();
}
function startBridge() {
  if (bridge && !bridge.killed) return {started:false, usb:reverseUsb()};
  fs.mkdirSync(dataDir(), {recursive:true});
  const usb = reverseUsb();
  const root = bridgeRoot();
  const log = fs.openSync(path.join(dataDir(), 'bridge.log'), 'a');
  bridge = spawn(process.execPath, [path.join(root, 'mac', 'bridge.js')], {
    cwd: root, detached:false, windowsHide:true, stdio:['ignore', log, log],
    env:{...process.env, ELECTRON_RUN_AS_NODE:'1', PASSPORT_DATA_DIR:dataDir(), PASSPORT_NO_BLE:'1', PASSPORT_HOST:'127.0.0.1'}
  });
  bridge.on('exit', () => { bridge = null; });
  return {started:true, usb};
}

app.whenReady().then(() => {
  window = new BrowserWindow({width:1080,height:760,minWidth:880,minHeight:650,backgroundColor:'#061b3a',
    title:'AI Passport',webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false}});
  window.setMenuBarVisibility(false);
  window.loadFile(path.join(__dirname,'index.html'));
  ipcMain.handle('bridge:start', () => startBridge());
  ipcMain.handle('bridge:stop', async () => { try { await api('/stop','POST'); } catch {} return true; });
  ipcMain.handle('bridge:status', async () => { try { return {ok:true,...await api('/status')}; } catch { return {ok:false}; } });
  ipcMain.handle('appearance:save', (_, appearance) => api('/appearance','POST',appearance));
  ipcMain.handle('modules:save', (_, modules) => api('/modules','POST',modules));
  ipcMain.handle('character:choose', async () => {
    const result = await dialog.showOpenDialog(window,{properties:['openFile'],filters:[{name:'PNG character',extensions:['png']}]});
    if (result.canceled) return null;
    const data=fs.readFileSync(result.filePaths[0]);
    if(data.length>8*1024*1024) throw new Error('PNG must be smaller than 8 MB');
    return data.toString('base64');
  });
});
app.on('before-quit', () => { if (bridge) bridge.kill(); });
app.on('window-all-closed', () => app.quit());

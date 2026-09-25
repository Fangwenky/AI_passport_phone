const {contextBridge, ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('passport', {
  start:()=>ipcRenderer.invoke('bridge:start'), stop:()=>ipcRenderer.invoke('bridge:stop'),
  status:()=>ipcRenderer.invoke('bridge:status'), saveAppearance:v=>ipcRenderer.invoke('appearance:save',v),
  saveModules:v=>ipcRenderer.invoke('modules:save',v), chooseCharacter:()=>ipcRenderer.invoke('character:choose')
});

const {contextBridge, ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('passport', {
  start:()=>ipcRenderer.invoke('bridge:start'), stop:()=>ipcRenderer.invoke('bridge:stop'),
  status:()=>ipcRenderer.invoke('bridge:status'), saveAppearance:v=>ipcRenderer.invoke('appearance:save',v),
  saveScheme:v=>ipcRenderer.invoke('scheme:save',v), activateScheme:id=>ipcRenderer.invoke('scheme:activate',id),
  schemeImage:id=>ipcRenderer.invoke('scheme:image',id),
  saveModules:v=>ipcRenderer.invoke('modules:save',v), chooseCharacter:()=>ipcRenderer.invoke('character:choose')
});

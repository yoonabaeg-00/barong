const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('barong', {
  calendar: {
    getStatus: () => ipcRenderer.invoke('calendar:get-status'),
    connect: () => ipcRenderer.invoke('calendar:connect'),
    disconnect: () => ipcRenderer.invoke('calendar:disconnect'),
    listEvents: () => ipcRenderer.invoke('calendar:list-events'),
  },
  openExternal: (url) => ipcRenderer.invoke('app:open-external', url),
  setExpanded: (expanded) => ipcRenderer.invoke('app:set-expanded', expanded),
})

import { useEffect, useState } from 'react';
import { IAppInfo } from '../../main/store';
import { ipcRenderer } from 'electron';
import { remote } from '@electron/remote';

export function UploadIPA() {
  const [apps, setApps] = useState<IAppInfo[]>([]);

  useEffect(() => {
    // 初始化加载存储数据
    const storedApps = remote.appStore.get();
    setApps(storedApps);
  }, []);

  const handleFileSelect = async () => {
    const { filePaths } = await remote.dialog.showOpenDialog({
      properties: ['openFile'],
      filters: [{ name: 'IPA Files', extensions: ['ipa'] }]
    });

    if (filePaths.length > 0) {
      try {
        const newApp = await ipcRenderer.invoke('parse-ipa', filePaths[0]);
        setApps(prev => [...prev, newApp]);
      } catch (error) {
        console.error('Error processing IPA:', error);
      }
    }
  };

  return (
    <div>
      <button onClick={handleFileSelect}>选择IPA文件</button>
      <div className="app-list">
        {apps.map((app, index) => (
          <div key={index} className="app-item">
            <img 
              src={`file://${app.iconPath}`} 
              alt="App Icon"
              style={{ width: 60, height: 60 }}
            />
            <div>
              <h3>{app.name}</h3>
              <p>版本: {app.version}</p>
              <p>Bundle ID: {app.bundleId}</p>
              <p>大小: {(app.size / 1024 / 1024).toFixed(2)} MB</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
} 
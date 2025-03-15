import { ipcMain } from 'electron';
import AdmZip from 'adm-zip';
import plist from 'plist';
import { appStore, IAppInfo } from './store';
import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';

// 在文件选择处理处添加：
ipcMain.handle('parse-ipa', async (_, filePath: string) => {
  try {
    const zip = new AdmZip(filePath);
    const entries = zip.getEntries();
    
    // 查找Info.plist
    const plistEntry = entries.find(e => 
      e.entryName.includes('.app/Info.plist') && 
      !e.entryName.includes('Watch/')
    );

    if (!plistEntry) throw new Error('Info.plist not found');
    
    // 解析plist
    const plistData = plist.parse(plistEntry.getData().toString('utf8'));
    const appName = plistData.CFBundleDisplayName || plistData.CFBundleName;
    
    // 查找图标
    const iconName = getPreferredIconName(plistData);
    const iconEntry = entries.find(e => 
      e.entryName.includes(`.app/${iconName}`)
    );

    // 保存图标到缓存
    const cacheDir = join(app.getPath('userData'), 'icons');
    if (!existsSync(cacheDir)) mkdirSync(cacheDir);
    
    const iconPath = join(cacheDir, `${Date.now()}.png`);
    if (iconEntry) {
      writeFileSync(iconPath, iconEntry.getData());
    }

    // 构建应用信息
    const appInfo: IAppInfo = {
      path: filePath,
      name: appName,
      bundleId: plistData.CFBundleIdentifier,
      version: plistData.CFBundleShortVersionString,
      iconPath: iconEntry ? iconPath : 'default-icon.png',
      size: zip.getSize(),
      timestamp: Date.now()
    };

    // 更新存储
    const existing = appStore.get();
    appStore.set([...existing, appInfo]);

    return appInfo;
  } catch (error) {
    console.error('IPA解析失败:', error);
    throw error;
  }
});

// 辅助函数获取首选图标
function getPreferredIconName(plistData: any): string {
  const icons = plistData.CFBundleIcons?.CFBundlePrimaryIcon?.CFBundleIconFiles;
  if (icons?.length) {
    const sizes = [180, 120, 152, 167, 1024]; // 常见尺寸排序
    for (const size of sizes) {
      const icon = icons.find((i: string) => i.includes(`${size}`));
      if (icon) return `${icon}@${size}px.png`;
    }
  }
  return 'AppIcon60x60@2x.png'; // 默认值
} 
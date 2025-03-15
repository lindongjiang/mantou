import Store from 'electron-store';

export interface IAppInfo {
  path: string;
  name: string;
  bundleId: string;
  version: string;
  iconPath: string;
  size: number;
  timestamp: number;
}

export const appStore = new Store<IAppInfo[]>({
  name: 'ipa-applications',
  defaults: []
}); 
import { registerPlugin } from '@capacitor/core';

import type { WalletPayPlugin } from './definitions';

const WalletPay = registerPlugin<WalletPayPlugin>('WalletPay', {
  web: () => import('./web').then((module) => new module.WalletPayWeb()),
});

export * from './definitions';
export { WalletPay };
export default WalletPay;

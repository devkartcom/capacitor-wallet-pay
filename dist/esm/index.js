import { registerPlugin } from '@capacitor/core';
const WalletPay = registerPlugin('WalletPay', {
    web: () => import('./web').then((module) => new module.WalletPayWeb()),
});
export * from './definitions';
export { WalletPay };
export default WalletPay;

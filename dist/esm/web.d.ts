import { WebPlugin } from '@capacitor/core';
import type { WalletPayPlugin, WalletPaymentResult } from './definitions';
/**
 * Web has its own wallet APIs (ApplePaySession, Google Pay JS); this plugin is
 * for the native apps only. `isAvailable` answers false so callers fall back to
 * their web flow; the other methods refuse.
 */
export declare class WalletPayWeb extends WebPlugin implements WalletPayPlugin {
    isAvailable(): Promise<{
        available: boolean;
    }>;
    requestPayment(): Promise<WalletPaymentResult>;
    completePayment(): Promise<void>;
}

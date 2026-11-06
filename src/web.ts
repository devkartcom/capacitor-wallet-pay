import { WebPlugin } from '@capacitor/core';

import type { WalletPayPlugin, WalletPaymentResult } from './definitions';

/**
 * Web has its own wallet APIs (ApplePaySession, Google Pay JS); this plugin is
 * for the native apps only. `isAvailable` answers false so callers fall back to
 * their web flow; the other methods refuse.
 */
export class WalletPayWeb extends WebPlugin implements WalletPayPlugin {
  async isAvailable(): Promise<{ available: boolean }> {
    return { available: false };
  }

  async requestPayment(): Promise<WalletPaymentResult> {
    throw Object.assign(new Error('Native wallet payments are not available on web.'), { code: 'NOT_AVAILABLE' });
  }

  async completePayment(): Promise<void> {
    return;
  }
}

'use strict';

Object.defineProperty(exports, '__esModule', { value: true });

var core = require('@capacitor/core');

const WalletPay = core.registerPlugin('WalletPay', {
    web: () => Promise.resolve().then(function () { return web; }).then((module) => new module.WalletPayWeb()),
});

/**
 * Web has its own wallet APIs (ApplePaySession, Google Pay JS); this plugin is
 * for the native apps only. `isAvailable` answers false so callers fall back to
 * their web flow; the other methods refuse.
 */
class WalletPayWeb extends core.WebPlugin {
    async isAvailable() {
        return { available: false };
    }
    async requestPayment() {
        throw Object.assign(new Error('Native wallet payments are not available on web.'), { code: 'NOT_AVAILABLE' });
    }
    async completePayment() {
        return;
    }
}

var web = /*#__PURE__*/Object.freeze({
    __proto__: null,
    WalletPayWeb: WalletPayWeb
});

exports.WalletPay = WalletPay;
exports["default"] = WalletPay;

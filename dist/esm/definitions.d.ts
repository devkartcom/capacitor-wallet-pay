/**
 * Gateway-agnostic Apple Pay / Google Pay for Capacitor.
 *
 * The plugin collects a wallet payment TOKEN and hands it back untouched; the
 * app sends it to its own server, which exchanges it with the payment gateway
 * (e.g. Finix `POST /payment_instruments` with `type: APPLE_PAY | GOOGLE_PAY`).
 * Nothing here talks to a gateway.
 *
 * Apple Pay token shape: `token` is the JSON STRING of
 * `{ token: { paymentData, paymentMethod, transactionIdentifier } }` — the full
 * PKPaymentToken wrapped under `token`, which is the `third_party_token` Finix
 * expects and the same string the web ApplePaySession flow builds.
 * Google Pay token shape: `token` is the raw
 * `paymentMethodData.tokenizationData.token` string ("pass without modification").
 */
export type WalletKind = 'applePay' | 'googlePay';
/** Card networks, in Google Pay spelling; mapped to PKPaymentNetwork on iOS. */
export type WalletCardNetwork = 'AMEX' | 'DISCOVER' | 'INTERAC' | 'JCB' | 'MASTERCARD' | 'VISA';
export interface ApplePayOptions {
    /**
     * The Apple Pay merchant identifier (`merchant.…`) in the app's in-app-payments
     * entitlement. Optional: when absent the plugin reads the host app's
     * Info.plist key `WalletPayMerchantIdentifier` (set it to `$(APPLE_PAY_MERCHANT_ID)`).
     * With neither, Apple Pay is reported unavailable.
     */
    merchantIdentifier?: string;
    /** Ask the customer for a billing postal address (Finix: lowers network dues). Default false. */
    requireBillingAddress?: boolean;
    /**
     * Ask Apple for a credential the merchant may charge again later (subscriptions,
     * auto top-up): sets `PKPaymentRequest.recurringPaymentRequest`. iOS 16.0+; on older
     * iOS it is ignored and a plain one-time request is sent. Takes precedence over
     * `deferred` when both are given.
     */
    recurring?: ApplePayRecurringRequest;
    /**
     * A single payment taken at a later date: sets `PKPaymentRequest.deferredPaymentRequest`.
     * iOS 16.4+ (Apple's own floor for deferred requests); ignored below.
     */
    deferred?: ApplePayDeferredRequest;
}
/** Calendar unit of a recurring billing interval (`NSCalendar.Unit`). */
export type ApplePayIntervalUnit = 'minute' | 'hour' | 'day' | 'month' | 'year';
export interface ApplePayRecurringRequest {
    /** Shown in the customer's Wallet, e.g. "Gold membership". */
    paymentDescription: string;
    /** HTTPS page where the customer manages or cancels the agreement. */
    managementURL: string;
    /** Shown on the sheet as the billing agreement. */
    billingAgreement?: string;
    regularBilling: {
        label: string;
        /** Decimal amount in MAJOR units as a string, e.g. "9.99". "0" for a variable amount. */
        amount: string;
        /** Default `month`. */
        intervalUnit?: ApplePayIntervalUnit;
        /** Default 1. */
        intervalCount?: number;
        /** ISO 8601. */
        startDate?: string;
        /** ISO 8601. */
        endDate?: string;
    };
}
export interface ApplePayDeferredRequest {
    paymentDescription: string;
    /** HTTPS page where the customer manages the payment. */
    managementURL: string;
    billingAgreement?: string;
    deferredBilling: {
        label: string;
        /** Decimal amount in MAJOR units as a string. */
        amount: string;
        /** ISO 8601 date the payment is taken. */
        deferredDate: string;
    };
    /** ISO 8601; before this date the customer can cancel for free. */
    freeCancellationDate?: string;
    /** IANA zone of `freeCancellationDate`, e.g. `America/Los_Angeles`. */
    freeCancellationDateTimeZone?: string;
}
export interface GooglePayOptions {
    /** `TEST` for sandbox gateways, `PRODUCTION` for live. */
    environment: 'TEST' | 'PRODUCTION';
    /** PAYMENT_GATEWAY tokenization: gateway name, e.g. `finix`. */
    gateway: string;
    /** The gateway's merchant id, e.g. the Finix merchant (or application) owner Identity `ID…`. */
    gatewayMerchantId: string;
    /** Google Pay & Wallet Console merchant id; required in PRODUCTION. */
    merchantId?: string;
    /** Default `['PAN_ONLY', 'CRYPTOGRAM_3DS']`. */
    allowedAuthMethods?: ('PAN_ONLY' | 'CRYPTOGRAM_3DS')[];
}
export interface WalletAvailabilityOptions {
    wallet: WalletKind;
    networks?: WalletCardNetwork[];
    applePay?: ApplePayOptions;
    googlePay?: GooglePayOptions;
}
export interface WalletAvailabilityResult {
    available: boolean;
    reason?: 'NO_MERCHANT_ID';
}
export interface WalletPaymentRequest {
    wallet: WalletKind;
    /** Decimal amount in MAJOR units as a string, e.g. "12.50". */
    amount: string;
    /** ISO 4217, e.g. "USD". */
    currencyCode: string;
    /** ISO 3166-1 alpha-2 merchant country, e.g. "US". */
    countryCode: string;
    /** Shown on the sheet as the payee. */
    merchantName: string;
    networks?: WalletCardNetwork[];
    applePay?: ApplePayOptions;
    googlePay?: GooglePayOptions;
}
export type WalletPaymentResult = {
    status: 'success';
    wallet: WalletKind;
    /** See the token shapes in this file's header. */
    token: string;
    /** Billing contact when requested (Apple Pay) / returned (Google Pay). */
    billingAddress?: {
        name?: string;
        line1?: string;
        line2?: string;
        city?: string;
        region?: string;
        postalCode?: string;
        countryCode?: string;
    };
} | {
    status: 'cancelled';
    wallet: WalletKind;
};
export interface WalletPayPlugin {
    /**
     * Whether this device can pay with the wallet (and, for Apple Pay, with the given networks).
     * `reason: 'NO_MERCHANT_ID'` when Apple Pay is unavailable because no merchant identifier was
     * passed or set in the app's Info.plist — a configuration gap, not a device answer, so the app
     * can log it.
     */
    isAvailable(options: WalletAvailabilityOptions): Promise<WalletAvailabilityResult>;
    /**
     * Open the wallet sheet. Resolves with the token once the customer authorizes,
     * or `cancelled`. Rejects with a coded error (`NOT_AVAILABLE`, `INVALID_ARGUMENT`,
     * `BUSY`, `WALLET_ERROR`).
     *
     * Apple Pay: the sheet STAYS OPEN on a spinner after resolving — call
     * `completePayment` with the charge outcome (it auto-fails after 25 s).
     * Google Pay: the sheet has already closed; `completePayment` is a no-op.
     */
    requestPayment(options: WalletPaymentRequest): Promise<WalletPaymentResult>;
    /** Close the Apple Pay sheet with the charge outcome. Safe to call when nothing is pending. */
    completePayment(options: {
        success: boolean;
    }): Promise<void>;
}

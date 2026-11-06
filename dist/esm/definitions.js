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
export {};

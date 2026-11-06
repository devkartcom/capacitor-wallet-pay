# @aybinv7/capacitor-wallet-pay

Gateway-agnostic Apple Pay (iOS, PassKit) and Google Pay (Android, Google Pay API) for Capacitor 8.
The plugin returns the raw wallet payment token; the app's server exchanges it with the gateway.

- iOS: `requestPayment({ wallet: 'applePay', … })` resolves with `token` = JSON string of
  `{ token: { paymentData, paymentMethod, transactionIdentifier } }` and keeps the sheet on its
  spinner until `completePayment({ success })` (auto-fails after 25 s).
- Android: `requestPayment({ wallet: 'googlePay', googlePay: { gateway, gatewayMerchantId, environment } })`
  resolves with `paymentMethodData.tokenizationData.token`. The library manifest does NOT declare
  `com.google.android.gms.wallet.api.enabled`; the host app adds it (per brand) to its own manifest.
- iOS: optional `applePay.recurring` (iOS 16.0+, `PKRecurringPaymentRequest`) or `applePay.deferred`
  (iOS 16.4+, `PKDeferredPaymentRequest`) for credentials charged again later; ignored on older iOS.
  `isAvailable` answers `reason: 'NO_MERCHANT_ID'` when no merchant identifier is configured.
- Web: `isAvailable` answers `false` (use the web wallet APIs).

Host app requirements: iOS `com.apple.developer.in-app-payments` entitlement with the merchant id, and
an Apple Pay Payment Processing Certificate from the gateway's CSR; Android Google Pay production
access for live use.

Pinned by tag like the other in-house plugins (`dist/` committed). Build: `npm install && npm run build`.

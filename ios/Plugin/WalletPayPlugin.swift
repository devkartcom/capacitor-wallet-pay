import Foundation
import Capacitor
import PassKit

/**
 * Apple Pay through PassKit. Returns the full PKPaymentToken as the JSON string
 * `{ "token": { "paymentData": …, "paymentMethod": …, "transactionIdentifier": … } }`
 * — the `third_party_token` a gateway such as Finix expects, and the same shape
 * the web ApplePaySession flow sends.
 *
 * The sheet stays open on its spinner after `requestPayment` resolves, until the
 * app calls `completePayment` with the charge outcome (auto-fails after 25 s so a
 * lost call can never leave the sheet stuck). Google Pay is Android-only.
 */
@objc(WalletPayPlugin)
public class WalletPayPlugin: CAPPlugin, CAPBridgedPlugin, PKPaymentAuthorizationControllerDelegate {
    public let identifier = "WalletPayPlugin"
    public let jsName = "WalletPay"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPayment", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "completePayment", returnType: CAPPluginReturnPromise)
    ]

    private static let completionTimeout: TimeInterval = 25

    private var controller: PKPaymentAuthorizationController?
    private var pendingCall: CAPPluginCall?
    private var pendingCompletion: ((PKPaymentAuthorizationResult) -> Void)?
    private var completionTimer: Timer?
    private var didAuthorize = false

    // MARK: - Networks

    private func paymentNetworks(_ names: [String]?) -> [PKPaymentNetwork] {
        let requested = names ?? ["VISA", "MASTERCARD", "AMEX", "DISCOVER"]
        return requested.compactMap { name in
            switch name.uppercased() {
            case "VISA": return .visa
            case "MASTERCARD": return .masterCard
            case "AMEX": return .amex
            case "DISCOVER": return .discover
            case "JCB": return .JCB
            case "INTERAC": return .interac
            default: return nil
            }
        }
    }

    /// The merchant id from the call, else the host app's Info.plist key
    /// `WalletPayMerchantIdentifier` (set to `$(APPLE_PAY_MERCHANT_ID)` so the
    /// brand build setting that also drives the in-app-payments entitlement is
    /// the single source). Empty or an unexpanded `$(` value → none.
    private func resolveMerchantIdentifier(_ applePay: [String: Any]) -> String? {
        if let fromCall = applePay["merchantIdentifier"] as? String, !fromCall.isEmpty {
            return fromCall
        }
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "WalletPayMerchantIdentifier") as? String,
           !fromPlist.isEmpty, !fromPlist.hasPrefix("$(") {
            return fromPlist
        }
        return nil
    }

    // MARK: - isAvailable

    @objc func isAvailable(_ call: CAPPluginCall) {
        guard call.getString("wallet") == "applePay" else {
            call.resolve(["available": false])
            return
        }
        guard resolveMerchantIdentifier(call.getObject("applePay") ?? [:]) != nil else {
            // A configuration gap, not a device answer: say so, so the app can log it once.
            call.resolve(["available": false, "reason": "NO_MERCHANT_ID"])
            return
        }
        let networks = paymentNetworks(call.getArray("networks", String.self))
        let available = PKPaymentAuthorizationController.canMakePayments()
            && PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks)
        call.resolve(["available": available])
    }

    // MARK: - requestPayment

    @objc func requestPayment(_ call: CAPPluginCall) {
        guard call.getString("wallet") == "applePay" else {
            call.reject("Only Apple Pay is available on iOS.", "NOT_AVAILABLE")
            return
        }
        guard pendingCall == nil, controller == nil else {
            call.reject("A wallet payment is already in progress.", "BUSY")
            return
        }
        let applePay = call.getObject("applePay") ?? [:]
        guard let merchantIdentifier = resolveMerchantIdentifier(applePay),
              let amountString = call.getString("amount"),
              let currencyCode = call.getString("currencyCode"),
              let countryCode = call.getString("countryCode") else {
            call.reject("merchantIdentifier, amount, currencyCode and countryCode are required.", "INVALID_ARGUMENT")
            return
        }
        let amount = NSDecimalNumber(string: amountString)
        if amount == NSDecimalNumber.notANumber || amount.compare(NSDecimalNumber.zero) != .orderedDescending {
            call.reject("amount must be a positive decimal string.", "INVALID_ARGUMENT")
            return
        }

        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantIdentifier
        request.countryCode = countryCode.uppercased()
        request.currencyCode = currencyCode.uppercased()
        request.supportedNetworks = paymentNetworks(call.getArray("networks", String.self))
        request.merchantCapabilities = [.threeDSecure]
        if (applePay["requireBillingAddress"] as? Bool) == true {
            request.requiredBillingContactFields = [.postalAddress, .name]
        }
        let label = call.getString("merchantName") ?? ""
        request.paymentSummaryItems = [PKPaymentSummaryItem(label: label, amount: amount, type: .final)]
        // Merchant-initiated charges later (renewals, auto top-up) need Apple's recurring or
        // deferred request so the gateway gets a reusable credential. Below the iOS floor the
        // option is ignored and a plain one-time request is sent.
        if #available(iOS 16.0, *), let recurring = applePay["recurring"] as? JSObject,
           let recurringRequest = WalletPayPlugin.recurringPaymentRequest(recurring) {
            request.recurringPaymentRequest = recurringRequest
        } else if #available(iOS 16.4, *), let deferred = applePay["deferred"] as? JSObject,
                  let deferredRequest = WalletPayPlugin.deferredPaymentRequest(deferred) {
            request.deferredPaymentRequest = deferredRequest
        }

        let authController = PKPaymentAuthorizationController(paymentRequest: request)
        authController.delegate = self
        controller = authController
        pendingCall = call
        didAuthorize = false
        call.keepAlive = true

        DispatchQueue.main.async {
            authController.present { presented in
                if !presented {
                    self.resetState()
                    call.reject("The Apple Pay sheet could not be opened.", "WALLET_ERROR")
                    self.bridge?.releaseCall(call)
                }
            }
        }
    }

    // MARK: - Recurring / deferred requests

    private static func decimal(_ value: Any?) -> NSDecimalNumber {
        if let string = value as? String {
            let number = NSDecimalNumber(string: string)
            return number == NSDecimalNumber.notANumber ? NSDecimalNumber.zero : number
        }
        if let number = value as? NSNumber {
            return NSDecimalNumber(decimal: number.decimalValue)
        }
        return NSDecimalNumber.zero
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: string) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let parsed = plain.date(from: string) { return parsed }
        let dayOnly = ISO8601DateFormatter()
        dayOnly.formatOptions = [.withFullDate]
        return dayOnly.date(from: string)
    }

    private static func calendarUnit(_ value: Any?) -> NSCalendar.Unit {
        switch (value as? String)?.lowercased() {
        case "minute": return .minute
        case "hour": return .hour
        case "day": return .day
        case "year": return .year
        default: return .month
        }
    }

    @available(iOS 16.0, *)
    private static func recurringPaymentRequest(_ options: JSObject) -> PKRecurringPaymentRequest? {
        guard let description = options["paymentDescription"] as? String, !description.isEmpty,
              let urlString = options["managementURL"] as? String, let managementURL = URL(string: urlString),
              let billing = options["regularBilling"] as? JSObject,
              let label = billing["label"] as? String else {
            return nil
        }
        let item = PKRecurringPaymentSummaryItem(label: label, amount: decimal(billing["amount"]))
        item.intervalUnit = calendarUnit(billing["intervalUnit"])
        if let count = billing["intervalCount"] as? NSNumber, count.intValue > 0 {
            item.intervalCount = count.intValue
        }
        if let start = date(billing["startDate"]) { item.startDate = start }
        if let end = date(billing["endDate"]) { item.endDate = end }
        let request = PKRecurringPaymentRequest(
            paymentDescription: description,
            regularBilling: item,
            managementURL: managementURL
        )
        if let agreement = options["billingAgreement"] as? String, !agreement.isEmpty {
            request.billingAgreement = agreement
        }
        return request
    }

    @available(iOS 16.4, *)
    private static func deferredPaymentRequest(_ options: JSObject) -> PKDeferredPaymentRequest? {
        guard let description = options["paymentDescription"] as? String, !description.isEmpty,
              let urlString = options["managementURL"] as? String, let managementURL = URL(string: urlString),
              let billing = options["deferredBilling"] as? JSObject,
              let label = billing["label"] as? String,
              let deferredDate = date(billing["deferredDate"]) else {
            return nil
        }
        let item = PKDeferredPaymentSummaryItem(label: label, amount: decimal(billing["amount"]))
        item.deferredDate = deferredDate
        let request = PKDeferredPaymentRequest(
            paymentDescription: description,
            deferredBilling: item,
            managementURL: managementURL
        )
        if let agreement = options["billingAgreement"] as? String, !agreement.isEmpty {
            request.billingAgreement = agreement
        }
        if let freeCancellation = date(options["freeCancellationDate"]) {
            request.freeCancellationDate = freeCancellation
            if let zoneName = options["freeCancellationDateTimeZone"] as? String, let zone = TimeZone(identifier: zoneName) {
                request.freeCancellationDateTimeZone = zone
            }
        }
        return request
    }

    // MARK: - completePayment

    @objc func completePayment(_ call: CAPPluginCall) {
        let success = call.getBool("success") ?? false
        DispatchQueue.main.async {
            self.finishAuthorization(success: success)
            call.resolve()
        }
    }

    private func finishAuthorization(success: Bool) {
        completionTimer?.invalidate()
        completionTimer = nil
        guard let completion = pendingCompletion else { return }
        pendingCompletion = nil
        completion(PKPaymentAuthorizationResult(status: success ? .success : .failure, errors: nil))
    }

    // MARK: - PKPaymentAuthorizationControllerDelegate

    public func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        guard let call = pendingCall else {
            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            return
        }
        didAuthorize = true

        let paymentDataObject = (try? JSONSerialization.jsonObject(with: payment.token.paymentData)) ?? [:]
        let method = payment.token.paymentMethod
        var methodType = "unknown"
        switch method.type {
        case .debit: methodType = "debit"
        case .credit: methodType = "credit"
        case .prepaid: methodType = "prepaid"
        case .store: methodType = "store"
        default: methodType = "unknown"
        }
        let tokenObject: [String: Any] = [
            "token": [
                "paymentData": paymentDataObject,
                "paymentMethod": [
                    "displayName": method.displayName ?? "",
                    "network": method.network?.rawValue ?? "",
                    "type": methodType
                ],
                "transactionIdentifier": payment.token.transactionIdentifier
            ]
        ]
        guard let tokenData = try? JSONSerialization.data(withJSONObject: tokenObject),
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            pendingCall = nil
            call.reject("The Apple Pay token could not be read.", "WALLET_ERROR")
            bridge?.releaseCall(call)
            return
        }

        var result: [String: Any] = ["status": "success", "wallet": "applePay", "token": tokenString]
        if let contact = payment.billingContact, let address = contact.postalAddress {
            var nameParts: [String] = []
            if let given = contact.name?.givenName { nameParts.append(given) }
            if let family = contact.name?.familyName { nameParts.append(family) }
            let streetLines = address.street.components(separatedBy: "\n")
            result["billingAddress"] = [
                "name": nameParts.joined(separator: " "),
                "line1": streetLines.first ?? "",
                "line2": streetLines.dropFirst().joined(separator: " "),
                "city": address.city,
                "region": address.state,
                "postalCode": address.postalCode,
                "countryCode": address.isoCountryCode.uppercased()
            ]
        }

        // Hold the sheet on its spinner until the app reports the charge outcome.
        pendingCompletion = completion
        completionTimer?.invalidate()
        completionTimer = Timer.scheduledTimer(withTimeInterval: WalletPayPlugin.completionTimeout, repeats: false) { [weak self] _ in
            self?.finishAuthorization(success: false)
        }

        pendingCall = nil
        call.resolve(result)
        bridge?.releaseCall(call)
    }

    public func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            DispatchQueue.main.async {
                // Closed before authorizing: the customer cancelled.
                if let call = self.pendingCall, !self.didAuthorize {
                    call.resolve(["status": "cancelled", "wallet": "applePay"])
                    self.bridge?.releaseCall(call)
                }
                self.finishAuthorization(success: false)
                self.resetState()
            }
        }
    }

    private func resetState() {
        completionTimer?.invalidate()
        completionTimer = nil
        controller = nil
        pendingCall = nil
        pendingCompletion = nil
        didAuthorize = false
    }
}

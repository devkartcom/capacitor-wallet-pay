package com.devsaran.wallet_pay;

import androidx.activity.result.ActivityResultLauncher;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.tasks.Task;
import com.google.android.gms.wallet.IsReadyToPayRequest;
import com.google.android.gms.wallet.PaymentData;
import com.google.android.gms.wallet.PaymentDataRequest;
import com.google.android.gms.wallet.PaymentsClient;
import com.google.android.gms.wallet.Wallet;
import com.google.android.gms.wallet.WalletConstants;
import com.google.android.gms.wallet.contract.ApiTaskResult;
import com.google.android.gms.wallet.contract.TaskResultContracts;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.List;

/**
 * Google Pay through the Google Pay API (Android). PAYMENT_GATEWAY tokenization
 * with a caller-supplied gateway (e.g. "finix") and gatewayMerchantId; returns
 * paymentMethodData.tokenizationData.token untouched. Apple Pay is iOS-only.
 *
 * The result arrives through an ActivityResultLauncher registered in load(),
 * i.e. while the bridge activity is being created (before it is STARTED, as
 * registerForActivityResult requires).
 */
@CapacitorPlugin(name = "WalletPay")
public class WalletPayPlugin extends Plugin {

    private ActivityResultLauncher<Task<PaymentData>> paymentDataLauncher;
    private PluginCall pendingCall;

    @Override
    public void load() {
        paymentDataLauncher = getActivity().registerForActivityResult(
            new TaskResultContracts.GetPaymentDataResult(),
            this::onPaymentDataResult
        );
    }

    private PaymentsClient paymentsClient(String environment) {
        int env = "PRODUCTION".equalsIgnoreCase(environment)
            ? WalletConstants.ENVIRONMENT_PRODUCTION
            : WalletConstants.ENVIRONMENT_TEST;
        Wallet.WalletOptions options = new Wallet.WalletOptions.Builder().setEnvironment(env).build();
        return Wallet.getPaymentsClient(getActivity(), options);
    }

    private JSONArray networks(PluginCall call) throws JSONException {
        JSArray requested = call.getArray("networks");
        JSONArray out = new JSONArray();
        if (requested != null && requested.length() > 0) {
            List<String> list = requested.toList();
            for (String n : list) out.put(n.toUpperCase());
        } else {
            out.put("VISA").put("MASTERCARD").put("AMEX").put("DISCOVER");
        }
        return out;
    }

    private JSONObject baseCardMethod(PluginCall call, JSObject googlePay) throws JSONException {
        JSONArray authMethods = new JSONArray();
        JSONArray requested = googlePay != null ? googlePay.optJSONArray("allowedAuthMethods") : null;
        if (requested != null && requested.length() > 0) {
            for (int i = 0; i < requested.length(); i++) authMethods.put(requested.getString(i));
        } else {
            authMethods.put("PAN_ONLY").put("CRYPTOGRAM_3DS");
        }
        JSONObject parameters = new JSONObject()
            .put("allowedAuthMethods", authMethods)
            .put("allowedCardNetworks", networks(call))
            .put("billingAddressRequired", true)
            .put("billingAddressParameters", new JSONObject().put("format", "MIN"));
        return new JSONObject().put("type", "CARD").put("parameters", parameters);
    }

    @PluginMethod
    public void isAvailable(PluginCall call) {
        if (!"googlePay".equals(call.getString("wallet"))) {
            call.resolve(new JSObject().put("available", false));
            return;
        }
        JSObject googlePay = call.getObject("googlePay", new JSObject());
        try {
            JSONObject request = new JSONObject()
                .put("apiVersion", 2)
                .put("apiVersionMinor", 0)
                .put("allowedPaymentMethods", new JSONArray().put(baseCardMethod(call, googlePay)));
            IsReadyToPayRequest ready = IsReadyToPayRequest.fromJson(request.toString());
            paymentsClient(googlePay.getString("environment", "TEST"))
                .isReadyToPay(ready)
                .addOnCompleteListener(task -> {
                    boolean available = false;
                    try {
                        Boolean result = task.getResult(Exception.class);
                        available = result != null && result;
                    } catch (Exception ignored) {
                        available = false;
                    }
                    call.resolve(new JSObject().put("available", available));
                });
        } catch (JSONException e) {
            call.resolve(new JSObject().put("available", false));
        }
    }

    @PluginMethod
    public void requestPayment(PluginCall call) {
        if (!"googlePay".equals(call.getString("wallet"))) {
            call.reject("Only Google Pay is available on Android.", "NOT_AVAILABLE");
            return;
        }
        if (pendingCall != null) {
            call.reject("A wallet payment is already in progress.", "BUSY");
            return;
        }
        JSObject googlePay = call.getObject("googlePay", new JSObject());
        String gateway = googlePay.getString("gateway");
        String gatewayMerchantId = googlePay.getString("gatewayMerchantId");
        String amount = call.getString("amount");
        String currencyCode = call.getString("currencyCode");
        String countryCode = call.getString("countryCode");
        String environment = googlePay.getString("environment", "TEST");
        String merchantId = googlePay.getString("merchantId");
        if (gateway == null || gatewayMerchantId == null || amount == null || currencyCode == null || countryCode == null) {
            call.reject("gateway, gatewayMerchantId, amount, currencyCode and countryCode are required.", "INVALID_ARGUMENT");
            return;
        }
        if ("PRODUCTION".equalsIgnoreCase(environment) && (merchantId == null || merchantId.isEmpty())) {
            call.reject("A Google Pay merchantId is required in PRODUCTION.", "INVALID_ARGUMENT");
            return;
        }
        try {
            JSONObject cardMethod = baseCardMethod(call, googlePay);
            cardMethod.put(
                "tokenizationSpecification",
                new JSONObject()
                    .put("type", "PAYMENT_GATEWAY")
                    .put("parameters", new JSONObject().put("gateway", gateway).put("gatewayMerchantId", gatewayMerchantId))
            );
            JSONObject merchantInfo = new JSONObject().put("merchantName", call.getString("merchantName", ""));
            if (merchantId != null && !merchantId.isEmpty()) merchantInfo.put("merchantId", merchantId);
            JSONObject request = new JSONObject()
                .put("apiVersion", 2)
                .put("apiVersionMinor", 0)
                .put("allowedPaymentMethods", new JSONArray().put(cardMethod))
                .put(
                    "transactionInfo",
                    new JSONObject()
                        .put("totalPrice", amount)
                        .put("totalPriceStatus", "FINAL")
                        .put("currencyCode", currencyCode.toUpperCase())
                        .put("countryCode", countryCode.toUpperCase())
                )
                .put("merchantInfo", merchantInfo);

            PaymentDataRequest dataRequest = PaymentDataRequest.fromJson(request.toString());
            pendingCall = call;
            call.setKeepAlive(true);
            Task<PaymentData> task = paymentsClient(environment).loadPaymentData(dataRequest);
            getActivity().runOnUiThread(() -> paymentDataLauncher.launch(task));
        } catch (JSONException e) {
            pendingCall = null;
            call.reject("The Google Pay request could not be built.", "INVALID_ARGUMENT");
        }
    }

    private void onPaymentDataResult(ApiTaskResult<PaymentData> result) {
        PluginCall call = pendingCall;
        pendingCall = null;
        if (call == null) return;
        int status = result.getStatus().getStatusCode();
        try {
            if (status == CommonStatusCodes.SUCCESS && result.getResult() != null) {
                JSONObject paymentData = new JSONObject(result.getResult().toJson());
                JSONObject methodData = paymentData.getJSONObject("paymentMethodData");
                String token = methodData.getJSONObject("tokenizationData").getString("token");
                JSObject out = new JSObject().put("status", "success").put("wallet", "googlePay").put("token", token);
                JSONObject info = methodData.optJSONObject("info");
                JSONObject billing = info != null ? info.optJSONObject("billingAddress") : null;
                if (billing != null) {
                    out.put(
                        "billingAddress",
                        new JSObject()
                            .put("name", billing.optString("name"))
                            .put("postalCode", billing.optString("postalCode"))
                            .put("countryCode", billing.optString("countryCode"))
                    );
                }
                call.resolve(out);
            } else if (status == CommonStatusCodes.CANCELED) {
                call.resolve(new JSObject().put("status", "cancelled").put("wallet", "googlePay"));
            } else {
                call.reject("Google Pay could not complete the payment.", "WALLET_ERROR");
            }
        } catch (JSONException e) {
            call.reject("The Google Pay token could not be read.", "WALLET_ERROR");
        } finally {
            getBridge().releaseCall(call);
        }
    }

    @PluginMethod
    public void completePayment(PluginCall call) {
        // The Google Pay sheet has already closed; nothing to complete.
        call.resolve();
    }
}

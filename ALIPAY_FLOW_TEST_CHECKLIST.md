# Alipay Flow Test Checklist

This guide covers the full Big Event Alipay flow in GatherGo, including admin setup, manual QR upload, automatic payment creation, payment status checks, and user-facing result rendering.

## Prerequisites

- Backend is running at `http://localhost:3000`
- A valid admin session/header is available
- A valid user id exists for checkout tests
- A Big Event already exists

Example shell variables:

```powershell
$BASE_URL = "http://localhost:3000"
$ADMIN_ID = "1"
$USER_ID = "101"
$EVENT_ID = "12"
```

## 1. Load admin payment methods

Request:

```powershell
curl "$BASE_URL/api/admin/big-events/$EVENT_ID/payment-methods" `
  -H "Accept: application/json" `
  -H "x-admin-id: $ADMIN_ID"
```

Expected response shape:

```json
{
  "event": {
    "id": 12,
    "payment_mode": "stripe_auto",
    "enable_promptpay": true,
    "enable_alipay": false,
    "stripe_enabled": true,
    "base_currency": "THB",
    "base_amount": 399,
    "exchange_rate_thb_per_cny": 4.8,
    "promptpay_amount_thb": 399,
    "alipay_amount_cny": null,
    "manual_promptpay_qr_url": null,
    "manual_alipay_qr_url": null
  },
  "methods": [
    {
      "method_type": "PROMPTPAY",
      "provider": "STRIPE",
      "is_active": true,
      "manual_available": false,
      "stripe_available": true,
      "amount": 399,
      "currency": "THB"
    }
  ]
}
```

## 2. Enable Alipay for automatic flow

Request:

```powershell
curl -X PUT "$BASE_URL/api/admin/big-events/$EVENT_ID/payment-methods" `
  -H "Content-Type: application/json" `
  -H "Accept: application/json" `
  -H "x-admin-id: $ADMIN_ID" `
  -d '{
    "payment_mode": "stripe_auto",
    "enable_promptpay": true,
    "enable_alipay": true,
    "stripe_enabled": true,
    "base_currency": "THB",
    "base_amount": 399,
    "exchange_rate_thb_per_cny": 4.80,
    "promptpay_amount_thb": 399,
    "alipay_amount_cny": 83.13
  }'
```

Expected response highlights:

```json
{
  "event": {
    "enable_promptpay": true,
    "enable_alipay": true,
    "payment_mode": "stripe_auto",
    "promptpay_amount_thb": 399,
    "alipay_amount_cny": 83.13
  },
  "methods": [
    { "method_type": "PROMPTPAY", "is_active": true, "stripe_available": true },
    { "method_type": "ALIPAY", "is_active": true, "stripe_available": true }
  ]
}
```

## 3. Hybrid mode setup

Use `hybrid` when PromptPay should still support manual QR while Alipay remains automatic.

PromptPay QR upload:

```powershell
curl -X POST "$BASE_URL/api/admin/events/$EVENT_ID/qr" `
  -H "Accept: application/json" `
  -H "x-admin-id: $ADMIN_ID" `
  -F "file=@C:\path\promptpay-qr.png" `
  -F "payment_method=promptpay"
```

Expected response highlights:

```json
{
  "message": "QR code uploaded successfully",
  "qr_payment_method": "promptpay",
  "manual_promptpay_qr_url": "http://localhost:3000/uploads/qr/event_promptpay.png"
}
```

Then switch mode to `hybrid`:

```powershell
curl -X PUT "$BASE_URL/api/admin/big-events/$EVENT_ID/payment-methods" `
  -H "Content-Type: application/json" `
  -H "Accept: application/json" `
  -H "x-admin-id: $ADMIN_ID" `
  -d '{
    "payment_mode": "hybrid",
    "enable_promptpay": true,
    "enable_alipay": true,
    "stripe_enabled": true,
    "base_currency": "THB",
    "base_amount": 399,
    "exchange_rate_thb_per_cny": 4.80,
    "promptpay_amount_thb": 399,
    "alipay_amount_cny": 83.13,
    "manual_promptpay_qr_url": "http://localhost:3000/uploads/qr/event_promptpay.png",
    "manual_alipay_qr_url": null
  }'
```

## 4. Load user payment methods

Request:

```powershell
curl "$BASE_URL/api/big-events/$EVENT_ID/payment-methods" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID"
```

Expected behavior:

- `PromptPay only` event returns only `PROMPTPAY`
- `Alipay only` event returns only `ALIPAY`
- `Both` returns both methods
- `Neither` returns an empty `methods` array
- `manual_qr + enable_alipay=true` should be rejected by admin update validation

## 5. Create automatic Alipay payment

Primary create route:

```powershell
curl -X POST "$BASE_URL/api/payments/airwallex/create" `
  -H "Content-Type: application/json" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID" `
  -d "{
    \"event_id\": $EVENT_ID,
    \"selected_payment_method_type\": \"alipay\",
    \"client_platform\": \"web\",
    \"os_type\": \"web\"
  }"
```

Expected response shape:

```json
{
  "ok": true,
  "payment_id": 9001,
  "booking_id": 7001,
  "booking_reference": "BK-20260314-007001",
  "payment_reference": "PAY-20260314-009001",
  "amount": 83.13,
  "currency": "CNY",
  "payment_method_type": "alipay",
  "provider": "airwallex_alipay",
  "provider_payment_intent_id": "int_xxx",
  "status": "pending",
  "checkout_url": "https://...",
  "redirect_url": "https://..."
}
```

Legacy route, same flow:

```powershell
curl -X POST "$BASE_URL/api/big-events/$EVENT_ID/checkout/alipay" `
  -H "Content-Type: application/json" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID" `
  -d "{ \"client_platform\": \"web\", \"os_type\": \"web\" }"
```

## 6. Check Alipay payment status

Dedicated Airwallex status route:

```powershell
$PAYMENT_ID = "9001"

curl "$BASE_URL/api/payments/airwallex/$PAYMENT_ID/status?user_id=$USER_ID" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID"
```

Generic payment status route:

```powershell
curl "$BASE_URL/api/payments/$PAYMENT_ID?user_id=$USER_ID" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID"
```

Expected response shape:

```json
{
  "paymentId": 9001,
  "booking_id": 7001,
  "booking_reference": "BK-20260314-007001",
  "event_id": 12,
  "event_title": "Spring Marathon",
  "amount": 83.13,
  "currency": "CNY",
  "method_type": "ALIPAY",
  "provider": "AIRWALLEX_ALIPAY",
  "payment_reference": "PAY-20260314-009001",
  "provider_txn_id": "attempt_xxx",
  "status": "pending",
  "receipt_no": null,
  "receipt_url": null,
  "failure_reason": null
}
```

## 7. Confirm or refresh Alipay payment

This route now syncs/finalizes Alipay status if needed:

```powershell
curl -X POST "$BASE_URL/api/payments/alipay/$PAYMENT_ID/confirm?user_id=$USER_ID" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID"
```

Expected successful response highlights:

```json
{
  "paymentId": 9001,
  "status": "paid",
  "method_type": "ALIPAY",
  "provider": "AIRWALLEX_ALIPAY",
  "payment_reference": "PAY-20260314-009001",
  "receipt_no": "RCPT-20260314-009001",
  "receipt_url": "http://localhost:3000/api/receipts/RCPT-20260314-009001/view"
}
```

## 8. Verify joined event / receipt state after success

Check joined events:

```powershell
curl "$BASE_URL/api/user/joined-events?user_id=$USER_ID" `
  -H "Accept: application/json" `
  -H "x-user-id: $USER_ID"
```

Look for:

- `payment_method_type = ALIPAY`
- `payment_status = paid` or equivalent
- `payment_reference`
- `receipt_no`
- `receipt_url`

Open receipt:

```powershell
$RECEIPT_NO = "RCPT-20260314-009001"
curl "$BASE_URL/api/receipts/$RECEIPT_NO/view"
```

Expected behavior:

- HTML receipt renders
- payment method shows Alipay
- provider shows Airwallex or configured provider
- payment reference and booking reference are present

## 9. Failure and cancellation checks

If provider returns failure/cancellation:

- `GET /api/payments/:paymentId` should return
  - `status = failed` or `cancelled`
  - `failure_reason` when available
- The booking should not be confirmed
- No participant should be added for the failed payment

## Final regression checklist

- PromptPay automatic flow still works
- PromptPay manual QR still works
- Alipay toggle appears in admin UI
- Alipay appears in user checkout when enabled
- Alipay success updates booking, participants, joined events, and receipt data
- Payment result and joined event detail render Alipay cleanly
- Admin cannot save `manual_qr` with `enable_alipay=true`

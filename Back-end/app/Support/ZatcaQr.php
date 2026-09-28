<?php

namespace App\Support;

use App\Models\Order;

/**
 * ============================================================================
 * ZATCA (هيئة الزكاة والضريبة والجمارك) — Phase 1 "simplified tax invoice" QR.
 *
 * The QR a Saudi VAT invoice must carry is a Base64-encoded TLV
 * (Tag-Length-Value) string of exactly five fields, in this order:
 *
 *   1  seller name
 *   2  VAT registration number
 *   3  invoice timestamp (ISO-8601)
 *   4  invoice total (with VAT)
 *   5  VAT total
 *
 * Each field is [tag byte][length byte][UTF-8 value bytes]; the five are
 * concatenated and Base64-encoded. The customer app and the dashboard render
 * that Base64 string as the QR image — a ZATCA reader decodes it back.
 *
 * This is Phase 1 (the printed/visible QR). Phase 2 (FATOORA platform
 * reporting with cryptographic stamps) is a separate integration and is not
 * required for the invoice to be compliant at point of sale.
 * ============================================================================
 */
class ZatcaQr
{
    /** The Base64 TLV for an order, or null when the order carries no VAT. */
    public static function forOrder(Order $order): ?string
    {
        if (empty($order->tax_number) || (float) $order->tax_amount <= 0) {
            return null;
        }

        return self::encode(
            sellerName: (string) ($order->seller_name ?? ''),
            vatNumber: (string) $order->tax_number,
            timestamp: $order->created_at->toIso8601String(),
            total: self::money($order->total),
            vatTotal: self::money($order->tax_amount),
        );
    }

    public static function encode(
        string $sellerName,
        string $vatNumber,
        string $timestamp,
        string $total,
        string $vatTotal,
    ): string {
        $tlv = self::tag(1, $sellerName)
            .self::tag(2, $vatNumber)
            .self::tag(3, $timestamp)
            .self::tag(4, $total)
            .self::tag(5, $vatTotal);

        return base64_encode($tlv);
    }

    /** One TLV field: tag byte + length byte + raw UTF-8 value. */
    private static function tag(int $tag, string $value): string
    {
        return chr($tag).chr(strlen($value)).$value;
    }

    private static function money(mixed $amount): string
    {
        return number_format((float) $amount, 2, '.', '');
    }
}

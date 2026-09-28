<?php

namespace App\Domain\Discovery;

use App\Models\QrCode as QrCodeModel;
use App\Models\Store;
use App\Support\TokenGenerator;
use Endroid\QrCode\Builder\Builder;
use Endroid\QrCode\ErrorCorrectionLevel;
use Endroid\QrCode\Writer\PngWriter;
use Endroid\QrCode\Writer\SvgWriter;
use Illuminate\Support\Facades\Storage;

/**
 * QR generation (spec §24).
 *
 * The encoded payload is always the public deep link —
 * https://wasla.sa/s/8F72K — never an internal id.
 */
class QrCodeService
{
    /**
     * Generate (or regenerate) a store's QR and store the image.
     */
    public function generate(Store $store): QrCodeModel
    {
        $link = $store->deepLink();

        /*
         * High error correction so the code still scans when it is printed on a
         * salon window, scuffed, or partially covered — these live in the
         * physical world, not on a screen.
         */
        $png = (new Builder(
            writer: new PngWriter,
            data: $link,
            errorCorrectionLevel: ErrorCorrectionLevel::High,
            size: 800,
            margin: 24,
        ))->build();

        $path = "qr/{$store->public_token}.png";
        Storage::disk('public')->put($path, $png->getString());

        // merchant_id is stamped from the store, not mass-assigned: QR
        // generation runs during registration and from seeders, where ambient
        // tenant context may not be set. See BelongsToTenant::createOwnedBy().
        $qr = QrCodeModel::query()->firstOrNew(['store_id' => $store->id]);

        $qr->fill([
            'public_token' => $store->public_token,
            'image_path' => $path,
            'is_active' => true,
        ]);

        $qr->forceFill(['merchant_id' => $store->merchant_id])->save();

        return $qr;
    }

    /**
     * Vector output for print. A salon printing A3 window decals needs SVG, not
     * an upscaled PNG.
     */
    public function svg(Store $store): string
    {
        return (new Builder(
            writer: new SvgWriter,
            data: $store->deepLink(),
            errorCorrectionLevel: ErrorCorrectionLevel::High,
            size: 800,
            margin: 24,
        ))->build()->getString();
    }

    /**
     * Issue a NEW token and QR, invalidating the old one (spec §24).
     *
     * For when printed codes are stolen or a merchant rebrands. Old printed
     * codes stop resolving, which is the point — so this bumps `version` for
     * the audit trail rather than pretending nothing changed.
     */
    public function regenerate(Store $store): QrCodeModel
    {
        $previous = $store->qrCode;

        $store->forceFill([
            'public_token' => TokenGenerator::uniqueStoreToken(Store::class),
        ])->save();

        $qr = $this->generate($store->refresh());

        $qr->forceFill(['version' => ($previous?->version ?? 0) + 1])->save();

        return $qr;
    }
}

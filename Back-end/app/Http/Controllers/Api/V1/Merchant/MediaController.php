<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * ============================================================================
 * STORE MEDIA — LOGO AND COVER (spec §35 "secure file uploads")
 *
 * The two images the customer app renders: the app-icon logo on the home card
 * and storefront, and the cover behind the storefront header.
 *
 * SECURITY (§35) — an upload endpoint is the softest target in any API, so:
 *
 *   · `image` + explicit mime allow-list, not a filename extension check
 *     (a .png extension proves nothing about the bytes)
 *   · size ceilings, because a merchant on a phone will happily send 12 MB
 *   · the stored name is a random string, NEVER the user's filename —
 *     that kills path traversal and double-extension tricks in one move
 *   · files land under the tenant's own folder on the public disk
 *   · the previous file is deleted, so a merchant swapping logos ten times
 *     does not leave ten orphans behind
 * ============================================================================
 */
class MediaController extends MerchantController
{
    /** Deliberately narrow: the formats browsers and phones actually produce. */
    private const ALLOWED_MIMES = ['image/jpeg', 'image/png', 'image/webp'];

    /**
     * POST /merchant/settings/media
     */
    public function upload(Request $request): JsonResponse
    {
        $request->validate([
            'type' => ['required', 'in:logo,cover'],
            'file' => [
                'required',
                'file',
                'image',
                'mimetypes:'.implode(',', self::ALLOWED_MIMES),
                // A logo is a small square; a cover is a wide photo.
                'max:5120',
            ],
        ]);

        $store = $this->merchantStore();
        $type = $request->string('type')->toString();

        /** @var UploadedFile $file */
        $file = $request->file('file');

        /*
         * Downscale at the door: a logo never renders above ~130px and a
         * cover above ~1300px, so storing a camera-original only slows every
         * customer's storefront open (and freezes the decode on-device).
         * The optimizer also returns the TRUE extension — a build without a
         * JPEG encoder may store the shrunk image as PNG/WebP instead.
         */
        [$binary, $extension] = \App\Support\ImageOptimizer::shrink(
            $file->getContent(),
            $type === 'logo' ? 512 : 1600,
            $file->getMimeType() ?? 'image/jpeg',
        );

        $path = sprintf(
            'stores/%d/%s-%s.%s',
            $store->id,
            $type,
            Str::lower(Str::random(24)),
            $extension,
        );

        $previous = $type === 'logo' ? $store->logo_path : $store->cover_path;

        Storage::disk('public')->put($path, $binary);

        $store->forceFill([
            $type === 'logo' ? 'logo_path' : 'cover_path' => $path,
        ])->save();

        // Remove the old file only after the new one is safely recorded.
        if ($previous !== null && $previous !== $path) {
            Storage::disk('public')->delete($previous);
        }

        return response()->json([
            'type' => $type,
            'path' => $path,
            'url' => Storage::disk('public')->url($path),
        ], 201);
    }

    /**
     * DELETE /merchant/settings/media/{type}
     */
    public function destroy(string $type): JsonResponse
    {
        if (! in_array($type, ['logo', 'cover'], true)) {
            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'NOT_FOUND',
            ], 404);
        }

        $store = $this->merchantStore();
        $column = $type === 'logo' ? 'logo_path' : 'cover_path';
        $current = $store->{$column};

        if ($current !== null) {
            Storage::disk('public')->delete($current);
        }

        $store->forceFill([$column => null])->save();

        return response()->json(['message' => __('merchant.media_removed')]);
    }
}

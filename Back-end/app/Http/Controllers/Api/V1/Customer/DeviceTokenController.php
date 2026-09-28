<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Models\DeviceToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Push registrations for the signed-in customer (spec §23).
 *
 * The app registers its FCM token here after the user grants permission, and
 * again whenever Firebase rotates it. Registration is idempotent — the same
 * (user, token) pair updates in place rather than piling up rows.
 */
class DeviceTokenController extends Controller
{
    /** POST /me/device-tokens */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:512'],
            'platform' => ['required', 'in:ios,android'],
            'app_version' => ['nullable', 'string', 'max:20'],
            'device_model' => ['nullable', 'string', 'max:255'],
        ]);

        // A token belongs to one device: if it moved to a different account,
        // reassign it rather than leaving the old user pushing to this phone.
        DeviceToken::query()
            ->where('token', $data['token'])
            ->where('user_id', '!=', $request->user()->id)
            ->delete();

        DeviceToken::updateOrCreate(
            ['user_id' => $request->user()->id, 'token' => $data['token']],
            [
                'platform' => $data['platform'],
                'app_version' => $data['app_version'] ?? null,
                'device_model' => $data['device_model'] ?? null,
                'last_seen_at' => now(),
            ],
        );

        return response()->json(null, 204);
    }

    /** DELETE /me/device-tokens — sign-out / notifications disabled. */
    public function destroy(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:512'],
        ]);

        DeviceToken::query()
            ->where('user_id', $request->user()->id)
            ->where('token', $data['token'])
            ->delete();

        return response()->json(null, 204);
    }
}

<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\DriverResource;
use App\Models\Driver;
use App\Models\User;
use App\Support\PhoneNumber;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * The merchant's delivery drivers. Creating a driver creates their login
 * (role `driver`, scoped to this merchant); the driver signs in to the driver
 * app with the phone + password entered here.
 */
class DriverController extends MerchantController
{
    /** GET /merchant/drivers */
    public function index(): AnonymousResourceCollection
    {
        return DriverResource::collection(
            Driver::query()
                ->where('store_id', $this->merchantStore()->id)
                ->withCount(['orders' => fn ($q) => $q->whereIn('status', ['accepted', 'preparing', 'ready', 'out_for_delivery'])])
                ->orderByDesc('is_active')
                ->orderBy('name')
                ->get(),
        );
    }

    /** POST /merchant/drivers */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'phone' => ['required', 'string', 'max:20'],
            'password' => ['required', 'string', 'min:8', 'max:255'],
            'vehicle' => ['sometimes', 'nullable', 'string', 'max:80'],
        ]);

        $phone = PhoneNumber::normalize($data['phone']);
        if ($phone === null) {
            return $this->phoneError(__('auth.invalid_phone'));
        }
        if (Driver::withoutTenancy()->where('phone', $phone)->exists()) {
            return $this->phoneError(__('merchant.driver_phone_taken'));
        }

        $driver = DB::transaction(function () use ($data, $phone) {
            // The login row. Phone stays on the driver profile (see migration);
            // the user gets a synthetic, unique email so nothing collides with a
            // customer account the same person may have.
            $user = User::create([
                'name' => $data['name'],
                'email' => 'driver-'.Str::lower(Str::random(16)).'@drivers.azir.sa',
                'password' => $data['password'],
                'role' => User::ROLE_DRIVER,
                'merchant_id' => app(TenantContext::class)->id(),
                'locale' => 'ar',
                'is_active' => true,
            ]);

            return Driver::create([
                'store_id' => $this->merchantStore()->id,
                'user_id' => $user->id,
                'name' => $data['name'],
                'phone' => $phone,
                'vehicle' => $data['vehicle'] ?? null,
                'is_active' => true,
            ]);
        });

        return response()->json(new DriverResource($driver->fresh()), 201);
    }

    /** PUT /merchant/drivers/{id} */
    public function update(int $id, Request $request): JsonResponse
    {
        $driver = Driver::findOrFail($id);
        $this->authorize('update', $driver);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:120'],
            'phone' => ['sometimes', 'string', 'max:20'],
            'password' => ['sometimes', 'nullable', 'string', 'min:8', 'max:255'],
            'vehicle' => ['sometimes', 'nullable', 'string', 'max:80'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (isset($data['phone'])) {
            $phone = PhoneNumber::normalize($data['phone']);
            if ($phone === null) {
                return $this->phoneError(__('auth.invalid_phone'));
            }
            if (Driver::withoutTenancy()->where('phone', $phone)->whereKeyNot($driver->id)->exists()) {
                return $this->phoneError(__('merchant.driver_phone_taken'));
            }
            $data['phone'] = $phone;
        }

        DB::transaction(function () use ($driver, $data): void {
            $driver->update(collect($data)->only(['name', 'phone', 'vehicle', 'is_active'])->all());

            $user = $driver->user;
            if ($user !== null) {
                $patch = [];
                if (isset($data['name'])) {
                    $patch['name'] = $data['name'];
                }
                if (! empty($data['password'])) {
                    $patch['password'] = $data['password'];
                }
                if (array_key_exists('is_active', $data)) {
                    $patch['is_active'] = (bool) $data['is_active'];
                }
                if ($patch !== []) {
                    $user->forceFill($patch)->save();
                }
                // A deactivated driver is signed out everywhere, immediately.
                if (array_key_exists('is_active', $data) && ! $data['is_active']) {
                    $user->tokens()->delete();
                }
            }
        });

        return response()->json(new DriverResource($driver->fresh()));
    }

    /** DELETE /merchant/drivers/{id} */
    public function destroy(int $id): JsonResponse
    {
        $driver = Driver::findOrFail($id);
        $this->authorize('delete', $driver);

        DB::transaction(function () use ($driver): void {
            // Orders keep their history (driver_id → null on delete); the login
            // goes with the profile.
            $user = $driver->user;
            $driver->delete();
            $user?->delete();
        });

        return response()->json(['message' => __('merchant.driver_deleted')]);
    }

    private function phoneError(string $message): JsonResponse
    {
        return response()->json([
            'message' => $message,
            'error_code' => 'VALIDATION_FAILED',
            'errors' => ['phone' => [$message]],
        ], 422);
    }
}

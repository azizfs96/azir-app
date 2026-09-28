<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Merchant\MerchantOnboardingService;
use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Support\PhoneNumber;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Merchant registration and the §11 onboarding wizard.
 *
 * Registration is PUBLIC; every other action requires the merchant's token but
 * NOT approval — a pending merchant must be able to finish setup and submit
 * (which is why these routes sit outside the merchant.approved middleware).
 */
class OnboardingController extends Controller
{
    public function __construct(
        private readonly MerchantOnboardingService $onboarding,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * POST /auth/merchant/register  — public.
     */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'business_name' => ['required', 'string', 'max:120'],
            'business_name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'business_type' => ['sometimes', 'string', Rule::in(array_keys(config('wasla.engines')))],
            'owner_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'phone' => ['required', 'string', 'max:20'],
            'password' => ['required', 'string', 'min:8', 'max:255'],
            'locale' => ['sometimes', 'in:ar,en'],
        ]);

        $phone = PhoneNumber::normalize($data['phone']);

        if ($phone === null) {
            return response()->json([
                'message' => __('auth.invalid_phone'),
                'error_code' => 'VALIDATION_FAILED',
                'errors' => ['phone' => [__('auth.invalid_phone')]],
            ], 422);
        }

        if (User::where('phone', $phone)->whereNot('role', User::ROLE_CUSTOMER)->exists()) {
            return response()->json([
                'message' => __('auth.phone_taken'),
                'error_code' => 'VALIDATION_FAILED',
                'errors' => ['phone' => [__('auth.phone_taken')]],
            ], 422);
        }

        $merchant = $this->onboarding->register([...$data, 'phone' => $phone]);
        $owner = $merchant->owner;

        return response()->json([
            'token' => $owner->createToken('merchant-dashboard')->plainTextToken,
            'user' => new UserResource($owner->load('merchant')),
            'store_token' => $merchant->store?->public_token,
            'next_step' => $merchant->onboarding_step,
        ], 201);
    }

    /**
     * GET /merchant/onboarding — where am I, and what is left?
     */
    public function show(Request $request): JsonResponse
    {
        $merchant = $this->tenant->merchant();
        $store = $merchant->store;

        return response()->json([
            'step' => $merchant->onboarding_step,
            'final_step' => \App\Models\Merchant::FINAL_ONBOARDING_STEP,
            'status' => $merchant->status,
            'is_published' => (bool) $store?->is_published,
            'completed' => $merchant->hasCompletedOnboarding(),

            // What still blocks going live — deliberately a short list (§11).
            'blockers' => $store !== null ? $this->onboarding->blockersFor($store) : ['store_missing'],

            'progress' => [
                'has_branch' => (bool) $store?->activeBranches()->exists(),
                'has_services' => (bool) $store?->services()->where('is_active', true)->exists(),
                'has_staff' => (bool) $store?->staff()->where('is_active', true)->exists(),
                'has_qr' => $store?->qrCode !== null,
            ],
        ]);
    }

    /**
     * POST /merchant/onboarding/step/{step}
     */
    public function advance(int $step, Request $request): JsonResponse
    {
        $merchant = $this->onboarding->advanceTo($this->tenant->merchant(), $step);

        return response()->json(['step' => $merchant->onboarding_step]);
    }

    /**
     * POST /merchant/onboarding/publish — step 9, go live (spec §42).
     */
    public function publish(Request $request): JsonResponse
    {
        $store = $this->tenant->merchant()->store;

        if ($store === null) {
            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'STORE_MISSING',
            ], 404);
        }

        $result = $this->onboarding->publish($store);

        if (! $result['published']) {
            return response()->json([
                'message' => __('merchant.cannot_publish'),
                'error_code' => 'ONBOARDING_INCOMPLETE',
                'blockers' => $result['blockers'],
            ], 422);
        }

        return response()->json([
            'message' => __('merchant.published'),
            'store_token' => $store->public_token,
            'deep_link' => $store->deepLink(),
            // Pending merchants go live only once an admin approves (§39).
            'awaiting_approval' => ! $store->merchant->isOperational(),
        ]);
    }
}

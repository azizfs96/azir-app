<?php

namespace App\Http\Controllers\Api\V1\PublicApi;

use App\Domain\Discovery\StoreResolver;
use App\Http\Controllers\Controller;
use App\Http\Resources\ServiceCategoryResource;
use App\Http\Resources\ServiceResource;
use App\Http\Resources\StorefrontResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Public store resolution — what a QR scan actually hits (spec §6, §31).
 *
 * Unauthenticated on purpose: someone scanning a salon's window should see the
 * storefront before being asked to sign in. Authentication is required only to
 * BOOK (spec §41).
 */
class StoreController extends Controller
{
    public function __construct(private readonly StoreResolver $resolver) {}

    /**
     * GET /stores/{token}
     *
     * The §31 payload. If the caller is a signed-in customer, the store is also
     * added to their My Stores — this is the "QR -> add merchant -> open" step.
     */
    public function show(string $token, Request $request): JsonResponse
    {
        $store = $this->resolver->resolve($token);

        if ($store === null) {
            return response()->json([
                'message' => __('errors.invalid_store_code'),
                'error_code' => 'STORE_NOT_FOUND',
            ], 404);
        }

        $this->resolver->recordAccess($store, $request, $request->user()?->customer);

        return response()->json(
            (new StorefrontResource($store))->toArray($request)
        );
    }

    /**
     * GET /stores/{token}/services
     */
    public function services(string $token, Request $request): JsonResponse
    {
        $store = $this->resolver->resolve($token);

        if ($store === null) {
            return response()->json([
                'message' => __('errors.invalid_store_code'),
                'error_code' => 'STORE_NOT_FOUND',
            ], 404);
        }

        return response()->json([
            'categories' => ServiceCategoryResource::collection($store->serviceCategories),
            'uncategorised' => ServiceResource::collection(
                $store->services->whereNull('service_category_id')
            ),
        ]);
    }
}

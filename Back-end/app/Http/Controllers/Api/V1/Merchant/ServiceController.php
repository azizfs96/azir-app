<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\ServiceResource;
use App\Models\Service;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Service management (spec §14).
 *
 * Note the total absence of merchant_id anywhere below: the BelongsToTenant
 * global scope filters reads and stamps writes, so these methods physically
 * cannot touch another merchant's catalogue (§4).
 */
class ServiceController extends MerchantController
{
    public function index(): AnonymousResourceCollection
    {
        return ServiceResource::collection(
            Service::query()
                ->where('store_id', $this->merchantStore()->id)
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);

        $service = Service::create([...$data, 'store_id' => $this->merchantStore()->id]);

        return response()->json(new ServiceResource($service), 201);
    }

    public function update(int $id, Request $request): JsonResponse
    {
        $service = Service::findOrFail($id);
        $this->authorize('update', $service);

        $service->update($this->validated($request, updating: true));

        return response()->json(new ServiceResource($service->fresh()));
    }

    /**
     * Soft delete. Past bookings reference this service, so the row must survive
     * or a merchant's history would develop holes.
     */
    public function destroy(int $id): JsonResponse
    {
        $service = Service::findOrFail($id);
        $this->authorize('delete', $service);

        $service->delete();

        return response()->json(['message' => __('merchant.service_deleted')]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $updating = false): array
    {
        $required = $updating ? 'sometimes' : 'required';

        return $request->validate([
            'name_ar' => [$required, 'string', 'max:120'],
            'name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'description_ar' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'description_en' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'service_category_id' => ['sometimes', 'nullable', 'integer', 'exists:service_categories,id'],
            'price' => [$required, 'numeric', 'min:0', 'max:99999.99'],
            // A zero-minute service would make the availability engine emit
            // infinite slots, so the floor is 5 minutes.
            'duration_minutes' => [$required, 'integer', 'min:5', 'max:1440'],
            'buffer_after_minutes' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0'],
        ]);
    }
}

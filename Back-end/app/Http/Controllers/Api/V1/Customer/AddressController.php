<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Http\Resources\CustomerAddressResource;
use App\Models\CustomerAddress;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * ============================================================================
 * CENTRAL DELIVERY ADDRESSES (feature expansion)
 *
 * The customer manages their addresses ONCE, in the app — not per store. A
 * store pulls the chosen one at checkout (see OrderController::store), so this
 * controller is a plain per-customer CRUD, never tenant-scoped and never
 * reachable by a merchant.
 * ============================================================================
 */
class AddressController extends Controller
{
    /** GET /me/addresses */
    public function index(Request $request): AnonymousResourceCollection
    {
        $addresses = $this->customer($request)->addresses()
            ->orderByDesc('is_default')
            ->orderByDesc('id')
            ->get();

        return CustomerAddressResource::collection($addresses);
    }

    /** POST /me/addresses */
    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);
        $customer = $this->customer($request);

        // The first address a customer saves is their default, whatever they ask.
        $isFirst = ! $customer->addresses()->exists();

        $address = $customer->addresses()->create([
            'label' => $data['label'] ?? 'home',
            'address_text' => $data['address_text'],
            'details' => $data['details'] ?? null,
            'latitude' => $data['latitude'] ?? null,
            'longitude' => $data['longitude'] ?? null,
            'is_default' => false,
        ]);

        if ($isFirst || ($data['is_default'] ?? false)) {
            $address->makeDefault();
        }

        return response()->json(new CustomerAddressResource($address->fresh()), 201);
    }

    /** PUT /me/addresses/{id} */
    public function update(int $id, Request $request): CustomerAddressResource|JsonResponse
    {
        $address = $this->customer($request)->addresses()->find($id);

        if ($address === null) {
            return $this->notFound();
        }

        $data = $this->validated($request);

        $address->update([
            'label' => $data['label'] ?? $address->label,
            'address_text' => $data['address_text'] ?? $address->address_text,
            'details' => array_key_exists('details', $data) ? $data['details'] : $address->details,
            'latitude' => array_key_exists('latitude', $data) ? $data['latitude'] : $address->latitude,
            'longitude' => array_key_exists('longitude', $data) ? $data['longitude'] : $address->longitude,
        ]);

        if ($data['is_default'] ?? false) {
            $address->makeDefault();
        }

        return new CustomerAddressResource($address->fresh());
    }

    /** DELETE /me/addresses/{id} */
    public function destroy(int $id, Request $request): JsonResponse
    {
        $address = $this->customer($request)->addresses()->find($id);

        if ($address === null) {
            return $this->notFound();
        }

        $wasDefault = $address->is_default;
        $customerId = $address->customer_id;
        $address->delete();

        // Never leave a customer with addresses but no default.
        if ($wasDefault) {
            CustomerAddress::query()
                ->where('customer_id', $customerId)
                ->orderByDesc('id')
                ->first()?->makeDefault();
        }

        return response()->json(null, 204);
    }

    /**
     * @return array<string, mixed>
     */
    private function validated(Request $request): array
    {
        $required = $request->isMethod('post') ? 'required' : 'sometimes';

        return $request->validate([
            'label' => ['sometimes', 'in:home,work,other'],
            'address_text' => [$required, 'string', 'max:255'],
            'details' => ['sometimes', 'nullable', 'string', 'max:255'],
            'latitude' => ['sometimes', 'nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['sometimes', 'nullable', 'numeric', 'between:-180,180'],
            'is_default' => ['sometimes', 'boolean'],
        ]);
    }

    private function customer(Request $request): \App\Models\Customer
    {
        return $request->user()->customer;
    }

    private function notFound(): JsonResponse
    {
        return response()->json(['message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND'], 404);
    }
}

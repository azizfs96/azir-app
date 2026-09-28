<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Models\CustomerCar;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use App\Http\Resources\CustomerCarResource;

/**
 * The customer's saved cars for curbside pickup — central, per-customer CRUD,
 * never tenant-scoped and never reachable by a merchant.
 */
class CarController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $cars = $this->customer($request)->cars()
            ->orderByDesc('is_default')->orderByDesc('id')->get();

        return CustomerCarResource::collection($cars);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request, true);
        $customer = $this->customer($request);
        $isFirst = ! $customer->cars()->exists();

        $car = $customer->cars()->create([
            'brand' => $data['brand'],
            'color' => $data['color'],
            'plate_letters' => $data['plate_letters'],
            'plate_numbers' => $data['plate_numbers'],
            'is_default' => false,
        ]);

        if ($isFirst || ($data['is_default'] ?? false)) {
            $car->makeDefault();
        }

        return response()->json(new CustomerCarResource($car->fresh()), 201);
    }

    public function destroy(int $id, Request $request): JsonResponse
    {
        $car = $this->customer($request)->cars()->find($id);

        if ($car === null) {
            return response()->json(['message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND'], 404);
        }

        $wasDefault = $car->is_default;
        $customerId = $car->customer_id;
        $car->delete();

        if ($wasDefault) {
            CustomerCar::query()->where('customer_id', $customerId)
                ->orderByDesc('id')->first()?->makeDefault();
        }

        return response()->json(null, 204);
    }

    /**
     * @return array<string, mixed>
     */
    private function validated(Request $request, bool $required): array
    {
        $rule = $required ? 'required' : 'sometimes';

        return $request->validate([
            'brand' => [$rule, 'string', 'max:40'],
            'color' => [$rule, 'string', 'max:30'],
            'plate_letters' => [$rule, 'string', 'max:12'],
            'plate_numbers' => [$rule, 'string', 'max:8'],
            'is_default' => ['sometimes', 'boolean'],
        ]);
    }

    private function customer(Request $request): \App\Models\Customer
    {
        return $request->user()->customer;
    }
}

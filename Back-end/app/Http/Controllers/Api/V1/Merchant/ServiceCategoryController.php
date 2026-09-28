<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\ServiceCategoryResource;
use App\Models\ServiceCategory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/** Service categories within one store — Hair, Nails, Facial (§14). */
class ServiceCategoryController extends MerchantController
{
    public function index(): AnonymousResourceCollection
    {
        return ServiceCategoryResource::collection(
            ServiceCategory::where('store_id', $this->merchantStore()->id)->orderBy('sort_order')->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $category = ServiceCategory::create([
            ...$this->validated($request),
            'store_id' => $this->merchantStore()->id,
        ]);

        return response()->json(new ServiceCategoryResource($category), 201);
    }

    public function update(int $id, Request $request): JsonResponse
    {
        $category = ServiceCategory::findOrFail($id);
        $this->authorize('update', $category);

        $category->update($this->validated($request, updating: true));

        return response()->json(new ServiceCategoryResource($category->fresh()));
    }

    public function destroy(int $id): JsonResponse
    {
        $category = ServiceCategory::findOrFail($id);
        $this->authorize('delete', $category);

        // Services outlive their category — they simply become uncategorised
        // rather than disappearing from the storefront.
        $category->services()->update(['service_category_id' => null]);
        $category->delete();

        return response()->json(['message' => __('merchant.category_deleted')]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $updating = false): array
    {
        return $request->validate([
            'name_ar' => [$updating ? 'sometimes' : 'required', 'string', 'max:80'],
            'name_en' => ['sometimes', 'nullable', 'string', 'max:80'],
            'icon' => ['sometimes', 'nullable', 'string', 'max:40'],
            'sort_order' => ['sometimes', 'integer', 'min:0'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}

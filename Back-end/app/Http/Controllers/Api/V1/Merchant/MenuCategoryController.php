<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\MenuCategoryResource;
use App\Models\MenuCategory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/**
 * Menu sections — البرجر / المشروبات / الحلى (RestaurantEngine).
 *
 * Same tenancy posture as ServiceController: merchant_id never appears here
 * because BelongsToTenant filters reads and stamps writes (§4).
 */
class MenuCategoryController extends MerchantController
{
    public function index(): AnonymousResourceCollection
    {
        return MenuCategoryResource::collection(
            MenuCategory::query()
                ->where('store_id', $this->merchantStore()->id)
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);

        $category = MenuCategory::create([...$data, 'store_id' => $this->merchantStore()->id]);

        return response()->json(new MenuCategoryResource($category), 201);
    }

    public function update(int $id, Request $request): JsonResponse
    {
        $category = MenuCategory::findOrFail($id);
        $this->authorize('update', $category);

        $category->update($this->validated($request, updating: true));

        return response()->json(new MenuCategoryResource($category->fresh()));
    }

    /**
     * Hard delete is safe: menu_items.menu_category_id nulls on delete, so
     * the dishes survive as "uncategorised" — nothing orphans, nothing loses
     * history (order lines snapshot their names anyway).
     */
    public function destroy(int $id): JsonResponse
    {
        $category = MenuCategory::findOrFail($id);
        $this->authorize('delete', $category);

        $category->delete();

        return response()->json(['message' => __('merchant.deleted')]);
    }

    /**
     * POST /menu/categories/{id}/image — a section icon/photo.
     *
     * Same hardening as every other upload: random stored name, tenant folder,
     * server-side downscale, previous file cleaned up.
     */
    public function image(int $id, Request $request): JsonResponse
    {
        $category = MenuCategory::findOrFail($id);
        $this->authorize('update', $category);

        $request->validate([
            'image' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:4096'],
        ]);

        $file = $request->file('image');

        [$binary, $extension] = \App\Support\ImageOptimizer::shrink(
            $file->getContent(),
            // A section thumbnail is small; 800px is plenty.
            800,
            $file->getMimeType() ?? 'image/jpeg',
        );

        $path = sprintf(
            'stores/%d/menu/cat-%s.%s',
            $category->store_id,
            Str::random(24),
            $extension,
        );

        $previous = $category->image_path;

        Storage::disk('public')->put($path, $binary);

        $category->forceFill(['image_path' => $path])->save();

        if ($previous) {
            Storage::disk('public')->delete($previous);
        }

        return response()->json(new MenuCategoryResource($category->fresh()));
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $updating = false): array
    {
        $required = $updating ? 'sometimes' : 'required';

        return $request->validate([
            'name_ar' => [$required, 'string', 'max:120'],
            'name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:100000'],
            'is_active' => ['sometimes', 'boolean'],
        ]);
    }
}

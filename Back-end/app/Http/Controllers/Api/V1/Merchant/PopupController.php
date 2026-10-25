<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\StorePopupResource;
use App\Models\StorePopup;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Pop-up ads (the merchant's "own app" moment): an image customers see when
 * they open this store in the app. Same tenancy stack as the menu — the store
 * comes from the tenant, the policy guards every write, images are optimised
 * and stored under the store's folder.
 */
class PopupController extends MerchantController
{
    /** GET /merchant/popups */
    public function index(): AnonymousResourceCollection
    {
        return StorePopupResource::collection(
            StorePopup::query()
                ->where('store_id', $this->merchantStore()->id)
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get(),
        );
    }

    /** POST /merchant/popups — created without an image; upload it next. */
    public function store(Request $request): JsonResponse
    {
        $popup = StorePopup::create([
            ...$this->validated($request),
            'store_id' => $this->merchantStore()->id,
        ]);

        return response()->json(new StorePopupResource($popup->fresh()), 201);
    }

    /** PUT /merchant/popups/{id} */
    public function update(int $id, Request $request): JsonResponse
    {
        $popup = StorePopup::findOrFail($id);
        $this->authorize('update', $popup);

        $popup->update($this->validated($request, updating: true));

        return response()->json(new StorePopupResource($popup->fresh()));
    }

    /** DELETE /merchant/popups/{id} */
    public function destroy(int $id): JsonResponse
    {
        $popup = StorePopup::findOrFail($id);
        $this->authorize('delete', $popup);

        if ($popup->image_path) {
            Storage::disk('public')->delete($popup->image_path);
        }
        $popup->delete();

        return response()->json(['deleted' => true]);
    }

    /** POST /merchant/popups/{id}/image */
    public function image(int $id, Request $request): JsonResponse
    {
        $popup = StorePopup::findOrFail($id);
        $this->authorize('update', $popup);

        $request->validate([
            'image' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:6144'],
        ]);

        $file = $request->file('image');

        // A pop-up fills the phone screen, so keep more pixels than a thumbnail.
        [$binary, $extension] = \App\Support\ImageOptimizer::shrink(
            $file->getContent(),
            1600,
            $file->getMimeType() ?? 'image/jpeg',
        );

        $path = sprintf('stores/%d/popups/%s.%s', $popup->store_id, Str::random(24), $extension);
        $previous = $popup->image_path;

        Storage::disk('public')->put($path, $binary);
        $popup->forceFill(['image_path' => $path])->save();

        if ($previous) {
            Storage::disk('public')->delete($previous);
        }

        return response()->json(new StorePopupResource($popup->fresh()));
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $updating = false): array
    {
        return $request->validate([
            'title_ar' => ['sometimes', 'nullable', 'string', 'max:120'],
            'title_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'frequency' => ['sometimes', Rule::in(StorePopup::FREQUENCIES)],
            'starts_at' => ['sometimes', 'nullable', 'date'],
            'ends_at' => ['sometimes', 'nullable', 'date', 'after_or_equal:starts_at'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:100000'],
        ]);
    }
}

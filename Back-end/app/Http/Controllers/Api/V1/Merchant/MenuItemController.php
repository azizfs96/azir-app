<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\MenuItemResource;
use App\Models\MenuItem;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Dishes and their options (RestaurantEngine).
 *
 * The option tree is edited through ONE endpoint that replaces the whole
 * structure per dish — the same replace-the-week pattern as staff schedules,
 * because that is how a form-based editor saves: the merchant edits the dish's
 * options as a unit, not one option at a time.
 */
class MenuItemController extends MerchantController
{
    public function index(): AnonymousResourceCollection
    {
        return MenuItemResource::collection(
            MenuItem::query()
                ->where('store_id', $this->merchantStore()->id)
                ->with('optionGroups.options')
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);

        $item = MenuItem::create([...$data, 'store_id' => $this->merchantStore()->id]);

        return response()->json(new MenuItemResource($item->load('optionGroups.options')), 201);
    }

    public function update(int $id, Request $request): JsonResponse
    {
        $item = MenuItem::findOrFail($id);
        $this->authorize('update', $item);

        $item->update($this->validated($request, updating: true));

        return response()->json(new MenuItemResource($item->fresh()->load('optionGroups.options')));
    }

    /**
     * Soft delete — the dashboard's order history keeps a readable dish list,
     * and order lines snapshot names/prices regardless (R1).
     */
    public function destroy(int $id): JsonResponse
    {
        $item = MenuItem::findOrFail($id);
        $this->authorize('delete', $item);

        $item->delete();

        return response()->json(['message' => __('merchant.deleted')]);
    }

    /**
     * PUT /menu/items/{id}/options — replace the dish's whole option tree.
     *
     * Atomic on purpose: a half-saved option tree (size group written, extras
     * lost) would sell mis-priced food. Either the new tree exists in full or
     * the old one is untouched.
     */
    public function options(int $id, Request $request): JsonResponse
    {
        $item = MenuItem::findOrFail($id);
        $this->authorize('update', $item);

        $data = $request->validate([
            'groups' => ['present', 'array', 'max:20'],
            'groups.*.name_ar' => ['required', 'string', 'max:120'],
            'groups.*.name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'groups.*.min_select' => ['required', 'integer', 'min:0', 'max:20'],
            'groups.*.max_select' => ['required', 'integer', 'min:1', 'max:20'],
            'groups.*.options' => ['required', 'array', 'min:1', 'max:30'],
            'groups.*.options.*.name_ar' => ['required', 'string', 'max:120'],
            'groups.*.options.*.name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'groups.*.options.*.price_delta' => ['sometimes', 'numeric', 'min:-9999.99', 'max:9999.99'],
            'groups.*.options.*.is_available' => ['sometimes', 'boolean'],
        ]);

        /*
         * Cross-field rules a validation string cannot express:
         * a group demanding more choices than it allows (min > max), or more
         * than it HAS (min > option count), is unfulfillable — the customer
         * could never order the dish at all.
         */
        foreach ($data['groups'] as $index => $group) {
            if ($group['min_select'] > $group['max_select']) {
                return response()->json([
                    'message' => __('validation.custom.option_group.min_exceeds_max'),
                    'error_code' => 'OPTION_GROUP_INVALID',
                    'group_index' => $index,
                ], 422);
            }

            if ($group['min_select'] > count($group['options'])) {
                return response()->json([
                    'message' => __('validation.custom.option_group.min_exceeds_options'),
                    'error_code' => 'OPTION_GROUP_INVALID',
                    'group_index' => $index,
                ], 422);
            }
        }

        DB::transaction(function () use ($item, $data): void {
            $item->optionGroups()->each(fn ($group) => $group->delete());

            foreach ($data['groups'] as $groupIndex => $groupData) {
                $group = $item->optionGroups()->create([
                    'store_id' => $item->store_id,
                    'name_ar' => $groupData['name_ar'],
                    'name_en' => $groupData['name_en'] ?? null,
                    'min_select' => $groupData['min_select'],
                    'max_select' => $groupData['max_select'],
                    'sort_order' => $groupIndex,
                ]);

                foreach ($groupData['options'] as $optionIndex => $optionData) {
                    $group->options()->create([
                        'store_id' => $item->store_id,
                        'name_ar' => $optionData['name_ar'],
                        'name_en' => $optionData['name_en'] ?? null,
                        'price_delta' => $optionData['price_delta'] ?? 0,
                        'is_available' => $optionData['is_available'] ?? true,
                        'sort_order' => $optionIndex,
                    ]);
                }
            }
        });

        return response()->json(new MenuItemResource($item->fresh()->load('optionGroups.options')));
    }

    /**
     * POST /menu/items/{id}/image — same hardening as store media uploads:
     * random stored name, tenant folder, previous file cleaned up.
     */
    public function image(int $id, Request $request): JsonResponse
    {
        $item = MenuItem::findOrFail($id);
        $this->authorize('update', $item);

        $request->validate([
            'image' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:4096'],
        ]);

        $file = $request->file('image');

        [$binary, $extension] = \App\Support\ImageOptimizer::shrink(
            $file->getContent(),
            1600,
            $file->getMimeType() ?? 'image/jpeg',
        );

        $path = sprintf(
            'stores/%d/menu/%s.%s',
            $item->store_id,
            Str::random(24),
            $extension,
        );

        $previous = $item->image_path;

        Storage::disk('public')->put($path, $binary);

        $item->forceFill(['image_path' => $path])->save();

        if ($previous) {
            Storage::disk('public')->delete($previous);
        }

        return response()->json(new MenuItemResource($item->fresh()->load('optionGroups.options')));
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
            'menu_category_id' => [
                'sometimes', 'nullable', 'integer',
                // Scoped to THIS store, not just existence — a category id from
                // another merchant must read as "no such category".
                Rule::exists('menu_categories', 'id')
                    ->where('store_id', $this->merchantStore()->id),
            ],
            'price' => [$required, 'numeric', 'min:0', 'max:99999.99'],
            'calories' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:20000'],
            'is_available' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            // "الأكثر طلباً" — the merchant's own hero pick, not a computed stat.
            'is_featured' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:100000'],
        ]);
    }
}

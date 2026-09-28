<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\BranchResource;
use App\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Branch management (spec §16). One branch or many. */
class BranchController extends MerchantController
{
    public function index(): JsonResponse
    {
        $branches = Branch::query()
            ->where('store_id', $this->merchantStore()->id)
            ->with('schedules')
            ->orderBy('sort_order')
            ->get();

        return response()->json([
            'data' => $branches->map(fn (Branch $branch) => [
                ...(new BranchResource($branch))->toArray(request()),
                'is_active' => $branch->is_active,
                'slot_interval_minutes' => $branch->slot_interval_minutes,
                'buffer_before_minutes' => $branch->buffer_before_minutes,
                'buffer_after_minutes' => $branch->buffer_after_minutes,
                'schedule' => $branch->schedules->map(fn ($s) => [
                    'day_of_week' => $s->day_of_week,
                    'opens_at' => $s->opens_at,
                    'closes_at' => $s->closes_at,
                    'is_closed' => $s->is_closed,
                ]),
            ]),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $branch = Branch::create([
            ...$this->validated($request),
            'store_id' => $this->merchantStore()->id,
        ]);

        return response()->json(new BranchResource($branch), 201);
    }

    public function update(int $id, Request $request): JsonResponse
    {
        $branch = Branch::findOrFail($id);
        $this->authorize('update', $branch);

        $branch->update($this->validated($request, updating: true));

        return response()->json(new BranchResource($branch->fresh()));
    }

    public function destroy(int $id): JsonResponse
    {
        $branch = Branch::findOrFail($id);
        $this->authorize('delete', $branch);

        // Refuse to remove the last branch: a store with none is unbookable,
        // and the customer-facing failure would be silent (zero slots forever).
        $remaining = Branch::where('store_id', $branch->store_id)->where('is_active', true)->count();

        if ($remaining <= 1) {
            return response()->json([
                'message' => __('merchant.last_branch'),
                'error_code' => 'LAST_BRANCH',
            ], 422);
        }

        $branch->delete();

        return response()->json(['message' => __('merchant.branch_deleted')]);
    }

    /** Replace a branch's weekly opening hours. Multiple rows per day = split shifts. */
    public function schedule(int $id, Request $request): JsonResponse
    {
        $branch = Branch::findOrFail($id);
        $this->authorize('update', $branch);

        $data = $request->validate([
            'schedule' => ['required', 'array', 'max:21'],
            'schedule.*.day_of_week' => ['required', 'integer', 'between:0,6'],
            'schedule.*.opens_at' => ['required', 'date_format:H:i'],
            'schedule.*.closes_at' => ['required', 'date_format:H:i'],
            'schedule.*.is_closed' => ['sometimes', 'boolean'],
        ]);

        $branch->schedules()->delete();

        foreach ($data['schedule'] as $row) {
            $branch->schedules()->create($row);
        }

        return response()->json(['message' => __('merchant.schedule_saved')]);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $updating = false): array
    {
        $required = $updating ? 'sometimes' : 'required';

        return $request->validate([
            'name_ar' => [$required, 'string', 'max:120'],
            'name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'address_line' => ['sometimes', 'nullable', 'string', 'max:255'],
            'city' => ['sometimes', 'nullable', 'string', 'max:80'],
            'latitude' => ['sometimes', 'nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['sometimes', 'nullable', 'numeric', 'between:-180,180'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:20'],
            'google_maps_url' => ['sometimes', 'nullable', 'url', 'max:500'],
            'slot_interval_minutes' => ['sometimes', 'integer', 'in:5,10,15,20,30,60'],
            'buffer_before_minutes' => ['sometimes', 'integer', 'min:0', 'max:120'],
            'buffer_after_minutes' => ['sometimes', 'integer', 'min:0', 'max:120'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0'],
        ]);
    }
}

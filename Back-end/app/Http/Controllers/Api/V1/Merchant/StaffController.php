<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Resources\StaffResource;
use App\Models\Staff;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Staff management (spec §15). Staff are OPTIONAL throughout.
 */
class StaffController extends MerchantController
{
    public function index(): JsonResponse
    {
        $staff = Staff::query()
            ->where('store_id', $this->merchantStore()->id)
            ->with(['services:id', 'schedules'])
            ->orderBy('sort_order')
            ->get();

        return response()->json([
            'data' => $staff->map(fn (Staff $member) => [
                'id' => $member->id,
                'name' => $member->name,
                'title_ar' => $member->title_ar,
                'title_en' => $member->title_en,
                'branch_id' => $member->branch_id,
                'gender' => $member->gender,
                'is_active' => $member->is_active,
                'is_bookable' => $member->is_bookable,
                // An empty list means "can perform everything" (§15) — surfaced
                // explicitly so the dashboard can say so rather than showing a
                // blank list that reads as "can perform nothing".
                'service_ids' => $member->services->pluck('id'),
                'performs_all_services' => $member->services->isEmpty(),
                'schedule' => $member->schedules->map(fn ($s) => [
                    'day_of_week' => $s->day_of_week,
                    'starts_at' => $s->starts_at,
                    'ends_at' => $s->ends_at,
                    'break_starts_at' => $s->break_starts_at,
                    'break_ends_at' => $s->break_ends_at,
                    'is_off' => $s->is_off,
                ]),
            ]),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);
        $services = $data['service_ids'] ?? null;
        unset($data['service_ids']);

        $staff = Staff::create([...$data, 'store_id' => $this->merchantStore()->id]);

        if (is_array($services)) {
            $staff->services()->sync($this->ownServiceIds($services));
        }

        return response()->json(new StaffResource($staff), 201);
    }

    public function update(int $id, Request $request): JsonResponse
    {
        $staff = Staff::findOrFail($id);
        $this->authorize('update', $staff);

        $data = $this->validated($request, updating: true);
        $services = $data['service_ids'] ?? null;
        unset($data['service_ids']);

        $staff->update($data);

        if (is_array($services)) {
            $staff->services()->sync($this->ownServiceIds($services));
        }

        return response()->json(new StaffResource($staff->fresh()));
    }

    public function destroy(int $id): JsonResponse
    {
        $staff = Staff::findOrFail($id);
        $this->authorize('delete', $staff);

        $staff->delete();

        return response()->json(['message' => __('merchant.staff_deleted')]);
    }

    /**
     * Replace a staff member's weekly schedule (spec §15).
     */
    public function schedule(int $id, Request $request): JsonResponse
    {
        $staff = Staff::findOrFail($id);
        $this->authorize('update', $staff);

        $data = $request->validate([
            'schedule' => ['required', 'array', 'max:21'],
            'schedule.*.day_of_week' => ['required', 'integer', 'between:0,6'],
            'schedule.*.starts_at' => ['required', 'date_format:H:i'],
            'schedule.*.ends_at' => ['required', 'date_format:H:i'],
            'schedule.*.break_starts_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'schedule.*.break_ends_at' => ['sometimes', 'nullable', 'date_format:H:i'],
            'schedule.*.is_off' => ['sometimes', 'boolean'],
        ]);

        // Replace wholesale: partial merges of weekly schedules are a rich
        // source of "why is Tuesday still showing last month's hours" bugs.
        $staff->schedules()->delete();

        foreach ($data['schedule'] as $row) {
            $staff->schedules()->create($row);
        }

        return response()->json(['message' => __('merchant.schedule_saved')]);
    }

    /**
     * Only ever attach services this merchant owns.
     *
     * @param  array<int, int>  $ids
     * @return array<int, int>
     */
    private function ownServiceIds(array $ids): array
    {
        return \App\Models\Service::whereIn('id', $ids)
            ->where('store_id', $this->merchantStore()->id)
            ->pluck('id')
            ->all();
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $updating = false): array
    {
        $required = $updating ? 'sometimes' : 'required';

        return $request->validate([
            'name' => [$required, 'string', 'max:120'],
            'title_ar' => ['sometimes', 'nullable', 'string', 'max:80'],
            'title_en' => ['sometimes', 'nullable', 'string', 'max:80'],
            'branch_id' => ['sometimes', 'nullable', 'integer', 'exists:branches,id'],
            'gender' => ['sometimes', 'nullable', 'in:male,female'],
            'bio' => ['sometimes', 'nullable', 'string', 'max:500'],
            'is_active' => ['sometimes', 'boolean'],
            'is_bookable' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0'],
            'service_ids' => ['sometimes', 'array'],
            'service_ids.*' => ['integer'],
        ]);
    }
}

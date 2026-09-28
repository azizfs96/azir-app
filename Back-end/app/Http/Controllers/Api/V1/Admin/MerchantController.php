<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Domain\Audit\AuditLogger;
use App\Http\Controllers\Controller;
use App\Models\Merchant;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * ============================================================================
 * ADMIN — MERCHANT APPROVAL (spec §39)
 *
 *   "Admin should be able to: view merchants, approve/reject merchants,
 *    suspend merchant, view platform metrics."
 *
 * This closes a real gap: every merchant registers as `pending`, and until
 * something approves them their store cannot be reached by any customer.
 * Before this existed, that only happened by editing the database.
 *
 * Admin queries run WITHOUT tenant scoping — this is the one part of the
 * platform that legitimately sees across merchants (ARCHITECTURE.md §4).
 * ============================================================================
 */
class MerchantController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    /**
     * GET /admin/merchants?status=pending
     */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['sometimes', Rule::in([
                Merchant::STATUS_PENDING, Merchant::STATUS_APPROVED,
                Merchant::STATUS_SUSPENDED, Merchant::STATUS_REJECTED,
            ])],
            'search' => ['sometimes', 'string', 'max:80'],
        ]);

        $query = Merchant::query()
            ->with(['owner:id,name,email,phone', 'store:id,merchant_id,public_token,name_ar,name_en,is_published'])
            ->withCount('bookings');

        if (isset($data['status'])) {
            $query->where('status', $data['status']);
        }

        if (isset($data['search'])) {
            $term = '%'.$data['search'].'%';
            $query->where(fn ($q) => $q
                ->where('display_name', 'like', $term)
                ->orWhere('legal_name', 'like', $term)
                ->orWhere('contact_phone', 'like', $term));
        }

        // Pending first: the admin's job is the approval queue, so it should
        // not need a filter to find its own work.
        return response()->json([
            'data' => $query
                ->orderByRaw("FIELD(status, 'pending', 'approved', 'suspended', 'rejected')")
                ->orderByDesc('created_at')
                ->paginate(30)
                ->through(fn (Merchant $merchant) => $this->present($merchant)),
        ]);
    }

    public function show(int $id): JsonResponse
    {
        $merchant = Merchant::with([
            'owner', 'store.bookingSettings', 'store.branches', 'store.services',
        ])->findOrFail($id);

        return response()->json([
            'merchant' => $this->present($merchant),
            'store' => $merchant->store === null ? null : [
                'token' => $merchant->store->public_token,
                'is_published' => (bool) $merchant->store->is_published,
                'branches' => $merchant->store->branches->count(),
                'services' => $merchant->store->services->count(),
            ],
        ]);
    }

    /**
     * POST /admin/merchants/{id}/approve
     */
    public function approve(int $id, Request $request): JsonResponse
    {
        $merchant = Merchant::findOrFail($id);

        if ($merchant->status === Merchant::STATUS_APPROVED) {
            return response()->json([
                'message' => __('admin.already_approved'),
                'error_code' => 'ALREADY_APPROVED',
            ], 422);
        }

        $previous = $merchant->status;

        $merchant->forceFill([
            'status' => Merchant::STATUS_APPROVED,
            'approved_at' => CarbonImmutable::now(),
            'approved_by_user_id' => $request->user()->id,
            'suspended_at' => null,
            'suspension_reason' => null,
        ])->save();

        $this->audit->record(
            'merchant.approved', $merchant,
            ['status' => $previous], ['status' => Merchant::STATUS_APPROVED],
            merchantId: $merchant->id,
        );

        return response()->json([
            'message' => __('admin.approved'),
            'merchant' => $this->present($merchant->fresh(['owner', 'store'])),
        ]);
    }

    /**
     * POST /admin/merchants/{id}/reject
     */
    public function reject(int $id, Request $request): JsonResponse
    {
        $data = $request->validate([
            'reason' => ['required', 'string', 'max:255'],
        ]);

        $merchant = Merchant::findOrFail($id);
        $previous = $merchant->status;

        $merchant->forceFill([
            'status' => Merchant::STATUS_REJECTED,
            'suspension_reason' => $data['reason'],
        ])->save();

        // A rejected merchant must not remain reachable by a printed QR.
        $merchant->store?->forceFill(['is_published' => false])->save();

        $this->audit->record(
            'merchant.rejected', $merchant,
            ['status' => $previous],
            ['status' => Merchant::STATUS_REJECTED, 'reason' => $data['reason']],
            merchantId: $merchant->id,
        );

        return response()->json([
            'message' => __('admin.rejected'),
            'merchant' => $this->present($merchant->fresh(['owner', 'store'])),
        ]);
    }

    /**
     * POST /admin/merchants/{id}/suspend
     *
     * Immediately stops the merchant taking bookings AND makes their store
     * unreachable — Store::isReachable() checks merchant status, so every
     * printed QR stops resolving the moment this runs.
     */
    public function suspend(int $id, Request $request): JsonResponse
    {
        $data = $request->validate([
            'reason' => ['required', 'string', 'max:255'],
        ]);

        $merchant = Merchant::findOrFail($id);
        $previous = $merchant->status;

        $merchant->forceFill([
            'status' => Merchant::STATUS_SUSPENDED,
            'suspended_at' => CarbonImmutable::now(),
            'suspension_reason' => $data['reason'],
        ])->save();

        $this->audit->record(
            'merchant.suspended', $merchant,
            ['status' => $previous],
            ['status' => Merchant::STATUS_SUSPENDED, 'reason' => $data['reason']],
            merchantId: $merchant->id,
        );

        return response()->json([
            'message' => __('admin.suspended'),
            'merchant' => $this->present($merchant->fresh(['owner', 'store'])),
        ]);
    }

    /**
     * POST /admin/merchants/{id}/reinstate
     */
    public function reinstate(int $id, Request $request): JsonResponse
    {
        $merchant = Merchant::findOrFail($id);

        if ($merchant->status !== Merchant::STATUS_SUSPENDED) {
            return response()->json([
                'message' => __('admin.not_suspended'),
                'error_code' => 'NOT_SUSPENDED',
            ], 422);
        }

        $merchant->forceFill([
            'status' => Merchant::STATUS_APPROVED,
            'suspended_at' => null,
            'suspension_reason' => null,
        ])->save();

        $this->audit->record(
            'merchant.reinstated', $merchant,
            ['status' => Merchant::STATUS_SUSPENDED],
            ['status' => Merchant::STATUS_APPROVED],
            merchantId: $merchant->id,
        );

        return response()->json([
            'message' => __('admin.reinstated'),
            'merchant' => $this->present($merchant->fresh(['owner', 'store'])),
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function present(Merchant $merchant): array
    {
        return [
            'id' => $merchant->id,
            'display_name' => $merchant->display_name,
            'legal_name' => $merchant->legal_name,
            'status' => $merchant->status,
            'contact_phone' => $merchant->contact_phone,
            'contact_email' => $merchant->contact_email,
            'onboarding_step' => $merchant->onboarding_step,
            'onboarding_complete' => $merchant->hasCompletedOnboarding(),
            'bookings_count' => $merchant->bookings_count ?? null,
            'suspension_reason' => $merchant->suspension_reason,
            'created_at' => $merchant->created_at?->toIso8601String(),
            'approved_at' => $merchant->approved_at?->toIso8601String(),
            'owner' => $merchant->relationLoaded('owner') && $merchant->owner !== null ? [
                'name' => $merchant->owner->name,
                'email' => $merchant->owner->email,
                'phone' => $merchant->owner->phone,
            ] : null,
            'store' => $merchant->relationLoaded('store') && $merchant->store !== null ? [
                'token' => $merchant->store->public_token,
                'name' => $merchant->store->name_ar,
                'is_published' => (bool) $merchant->store->is_published,
            ] : null,
        ];
    }
}

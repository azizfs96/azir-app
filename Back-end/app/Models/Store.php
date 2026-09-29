<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use App\Support\TokenGenerator;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * The customer-facing storefront (spec §8, §31).
 *
 * `public_token` is the QR payload and the deep-link segment. It is generated
 * once on create and is the ONLY identifier ever exposed publicly (spec §24).
 *
 * `business_type` selects the BusinessEngine at runtime, which is what makes a
 * future Restaurant vertical additive rather than a rewrite (ARCHITECTURE.md §2).
 */
#[Fillable([
    'business_type', 'name_ar', 'name_en', 'description_ar', 'description_en',
    'logo_path', 'cover_path', 'brand_color', 'timezone', 'currency', 'gender_policy',
    'phone', 'instagram',
])]
class Store extends Model
{
    use BelongsToTenant, HasFactory, SoftDeletes;

    protected function casts(): array
    {
        return [
            'is_published' => 'boolean',
            'published_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        // The token must exist before the row does — the QR depends on it.
        static::creating(function (Store $store): void {
            $store->public_token ??= TokenGenerator::uniqueStoreToken(self::class);
        });
    }

    /**
     * Public routes resolve stores by token, never by id (spec §24).
     */
    public function getRouteKeyName(): string
    {
        return 'public_token';
    }

    // ---- Relations ----

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }

    public function activeBranches(): HasMany
    {
        return $this->branches()->where('is_active', true)->orderBy('sort_order');
    }

    public function services(): HasMany
    {
        return $this->hasMany(Service::class);
    }

    public function serviceCategories(): HasMany
    {
        return $this->hasMany(ServiceCategory::class);
    }

    public function staff(): HasMany
    {
        return $this->hasMany(Staff::class);
    }

    public function bookingSettings(): HasOne
    {
        return $this->hasOne(BookingSettings::class);
    }

    public function qrCode(): HasOne
    {
        return $this->hasOne(QrCode::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    // ---- Derived state ----

    /**
     * Whether the customer should be asked to choose a branch at all (spec §16).
     *
     * Two conditions, and BOTH must hold: the merchant enabled the choice, and
     * there is genuinely more than one branch to choose between. A merchant who
     * flips the toggle on while having one branch still gets a one-tap flow.
     */
    public function requiresBranchSelection(): bool
    {
        return (bool) $this->bookingSettings?->branch_selection
            && $this->activeBranches()->count() > 1;
    }

    /**
     * The branch to use when the customer is never asked (spec §16).
     */
    public function defaultBranch(): ?Branch
    {
        return $this->activeBranches()->first();
    }

    public function displayName(string $locale = 'ar'): string
    {
        return $locale === 'en'
            ? ($this->name_en ?: $this->name_ar)
            : $this->name_ar;
    }

    /**
     * Is the store open right now? True if any active branch is within its
     * opening hours (branch timezone, honouring split shifts). A store that has
     * set NO hours anywhere is treated as open — hours simply aren't restricting
     * it — so the badge never wrongly reads "closed" for an unconfigured store.
     */
    public function isOpenNow(): bool
    {
        // Prefer already-loaded branches+schedules (list endpoints eager-load
        // them); otherwise fetch once here. Never lazy-loads.
        $branches = $this->relationLoaded('activeBranches')
            && $this->activeBranches->every(fn ($b) => $b->relationLoaded('schedules'))
            ? $this->activeBranches
            : $this->activeBranches()->with('schedules')->get();

        $anyConfigured = false;
        foreach ($branches as $branch) {
            if ($branch->schedules->isEmpty()) {
                continue;
            }
            $anyConfigured = true;
            if (\App\Domain\Merchant\OpeningHoursSummary::isBranchOpenNow($branch)) {
                return true;
            }
        }

        return ! $anyConfigured;
    }

    /**
     * The URL encoded in the QR and printed on the merchant's window (spec §38).
     */
    public function deepLink(): string
    {
        return rtrim(config('wasla.web_url'), '/')
            .config('wasla.store_link_path')
            .'/'.$this->public_token;
    }

    /** @param  Builder<Store>  $query */
    public function scopePublished(Builder $query): Builder
    {
        return $query->where('is_published', true);
    }

    /**
     * A store is only reachable by a customer if it is published AND its
     * merchant is approved and not suspended.
     */
    public function isReachable(): bool
    {
        return $this->is_published && $this->merchant->isOperational();
    }
}

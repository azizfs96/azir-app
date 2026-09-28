<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

/**
 * One role-discriminated user table (spec §34; ARCHITECTURE.md §5.2).
 *
 * `merchant_id` here is the ROOT of tenant isolation — TenantContext derives the
 * active tenant from this column and nothing else (§4).
 */
#[Fillable([
    'name', 'email', 'phone', 'password', 'role', 'merchant_id', 'locale', 'is_active',
])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    public const ROLE_CUSTOMER = 'customer';

    public const ROLE_MERCHANT_OWNER = 'merchant_owner';

    public const ROLE_MERCHANT_STAFF = 'merchant_staff';

    public const ROLE_ADMIN = 'admin';

    /**
     * PHP-side defaults, not just DB column defaults.
     *
     * A freshly created User otherwise has is_active === null in memory for the
     * rest of the request, so the very check that guards sign-in ("is this
     * account disabled?") rejects brand new customers.
     */
    protected $attributes = [
        'role' => self::ROLE_CUSTOMER,
        'locale' => 'ar',
        'is_active' => true,
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'phone_verified_at' => 'datetime',
            'last_login_at' => 'datetime',
            'is_active' => 'boolean',
            'password' => 'hashed',
        ];
    }

    // ---- Relations ----

    public function customer(): HasOne
    {
        return $this->hasOne(Customer::class);
    }

    /**
     * The tenant this user acts within. Null for customers and admins.
     */
    public function merchant(): BelongsTo
    {
        return $this->belongsTo(Merchant::class);
    }

    public function deviceTokens(): HasMany
    {
        return $this->hasMany(DeviceToken::class);
    }

    // ---- Role checks ----

    public function isCustomer(): bool
    {
        return $this->role === self::ROLE_CUSTOMER;
    }

    public function isAdmin(): bool
    {
        return $this->role === self::ROLE_ADMIN;
    }

    /**
     * Any user acting inside a merchant tenant — owner or staff.
     */
    public function isMerchantUser(): bool
    {
        return in_array($this->role, [self::ROLE_MERCHANT_OWNER, self::ROLE_MERCHANT_STAFF], true);
    }

    public function isMerchantOwner(): bool
    {
        return $this->role === self::ROLE_MERCHANT_OWNER;
    }
}

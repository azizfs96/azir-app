<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Http\Controllers\Controller;
use App\Models\Store;
use App\Support\TenantContext;

/**
 * Base for every merchant endpoint.
 *
 * Resolving the store through the TENANT (never a request parameter) is the
 * single habit that keeps §26 true across all of these controllers.
 */
abstract class MerchantController extends Controller
{
    public function __construct(protected readonly TenantContext $tenant) {}

    /**
     * The acting merchant's store. Tenant-derived, so it cannot be spoofed.
     *
     * Named merchantStore() rather than store() so it never collides with the
     * REST `store()` verb on resource controllers.
     */
    protected function merchantStore(): Store
    {
        // The global scope already limits this to the active tenant.
        return Store::query()
            ->where('merchant_id', $this->tenant->idOrFail())
            ->firstOrFail();
    }
}

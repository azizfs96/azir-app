<?php

namespace App\Engines;

use App\Models\Store;
use InvalidArgumentException;

/**
 * Resolves a Store's business_type to its engine (ARCHITECTURE.md §2.1).
 *
 * Registration is config-driven (config/wasla.php `engines`), so adding a
 * vertical is a config line plus a class — never a change here.
 */
class BusinessEngineRegistry
{
    /** @var array<string, BusinessEngine> */
    private array $resolved = [];

    /**
     * @param  array<string, class-string<BusinessEngine>>  $engines
     */
    public function __construct(
        private readonly array $engines,
        private readonly string $defaultKey,
    ) {}

    public function for(Store $store): BusinessEngine
    {
        return $this->get($store->business_type ?: $this->defaultKey);
    }

    public function get(string $key): BusinessEngine
    {
        if (isset($this->resolved[$key])) {
            return $this->resolved[$key];
        }

        if (! isset($this->engines[$key])) {
            throw new InvalidArgumentException(
                "No business engine registered for [{$key}]. Register it in config/wasla.php."
            );
        }

        return $this->resolved[$key] = app($this->engines[$key]);
    }

    public function has(string $key): bool
    {
        return isset($this->engines[$key]);
    }

    /**
     * Engines a merchant may choose during onboarding step 2.
     * The MVP returns exactly one — Beauty & Wellness (spec §2).
     *
     * @return array<int, BusinessEngine>
     */
    public function available(): array
    {
        return array_map(fn (string $key) => $this->get($key), array_keys($this->engines));
    }
}

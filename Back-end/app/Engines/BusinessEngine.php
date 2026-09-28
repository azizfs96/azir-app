<?php

namespace App\Engines;

use App\Models\Store;

/**
 * The Core Engine / Business Engine boundary (spec §3, §43, §44).
 *
 * ============================================================================
 * THE ARCHITECTURAL RULE THIS EXISTS TO ENFORCE:
 *
 *   "Build the platform so that a new merchant is created through data and
 *    configuration, not through new code."
 *
 * Core owns identity, merchants, stores, branches, customers, QR, payments and
 * notifications. It does NOT know what a "service" or an "appointment" is.
 *
 * An engine owns its catalog shape, its configuration schema, and — critically
 * — the ORDERED STEP LIST that the customer app walks. Core executes what the
 * engine declares.
 *
 * Adding Restaurant Ordering later = one class implementing this interface,
 * plus its own tables, plus one line in config/wasla.php. No core table
 * changes, no Flutter release, no React release (spec §44).
 * ============================================================================
 *
 * Note: quoting and fulfilment (turning a validated selection into a Booking)
 * live in the Booking domain services rather than here, because they need the
 * availability engine and the payment abstraction. The engine's job is to
 * DESCRIBE the experience; core performs it.
 */
interface BusinessEngine
{
    /**
     * Stable key stored in stores.business_type. Never rename — it is data.
     */
    public function key(): string;

    /**
     * Human label for merchant onboarding step 2 (spec §11).
     *
     * @return array{ar: string, en: string}
     */
    public function label(): array;

    /**
     * Which configuration toggles this engine understands, with types and
     * defaults. Drives the merchant Settings UI, so a new toggle appears in the
     * dashboard without a React change.
     *
     * @return array<string, array{type: string, default: mixed, group: string}>
     */
    public function configurationSchema(): array;

    /**
     * Defaults applied when a store of this type is created.
     *
     * @return array<string, mixed>
     */
    public function defaultConfiguration(): array;

    /**
     * ====================================================================
     * The customer journey, AS DATA (spec §9, §31; ARCHITECTURE.md §2.2).
     *
     * This is the method that keeps merchant variation out of the app binary.
     * Merchant A (staff selection on) and Merchant B (off) get different step
     * lists from the same code, and Flutter simply walks whatever it receives.
     * ====================================================================
     *
     * @return array<int, array<string, mixed>>
     */
    public function flow(Store $store): array;

    /**
     * The bookable catalog for this store, shaped for the customer app.
     *
     * @return array<string, mixed>
     */
    public function catalog(Store $store): array;
}

<?php

namespace App\Console\Commands;

use App\Models\Branch;
use App\Support\MapsLink;
use Illuminate\Console\Command;

/**
 * Backfill: branches saved with a maps link but no coordinates (short links
 * pasted before the server learned to expand them) get their pin now.
 *
 *   php artisan branches:resolve-pins
 */
class ResolveBranchPins extends Command
{
    protected $signature = 'branches:resolve-pins {--dry-run : Show what would change without saving}';

    protected $description = 'Fill latitude/longitude for branches whose Google Maps link has no coordinates yet';

    public function handle(): int
    {
        $branches = Branch::query()
            ->withoutGlobalScopes()
            ->whereNull('latitude')
            ->whereNotNull('google_maps_url')
            ->get();

        if ($branches->isEmpty()) {
            $this->info('Every branch with a maps link already has a pin.');

            return self::SUCCESS;
        }

        $resolved = 0;
        foreach ($branches as $branch) {
            $pin = MapsLink::resolve($branch->google_maps_url);
            if ($pin === null) {
                $this->warn("#{$branch->id} {$branch->name_ar}: no coordinates found in {$branch->google_maps_url}");

                continue;
            }
            [$lat, $lng] = $pin;
            $this->line("#{$branch->id} {$branch->name_ar}: {$lat}, {$lng}");
            if (! $this->option('dry-run')) {
                $branch->forceFill(['latitude' => $lat, 'longitude' => $lng])->save();
            }
            $resolved++;
        }

        $this->info("Resolved {$resolved} of {$branches->count()} branch(es)".($this->option('dry-run') ? ' (dry run, nothing saved)' : '').'.');

        return self::SUCCESS;
    }
}

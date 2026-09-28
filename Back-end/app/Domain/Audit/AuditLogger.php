<?php

namespace App\Domain\Audit;

use App\Models\AuditLog;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Audit trail for important actions (spec §35).
 *
 *   "Audit logs for important merchant actions."
 *
 * Deliberately explicit rather than an automatic model observer: logging every
 * write would bury the handful of entries that actually matter (who approved
 * this merchant, who suspended them, who changed a price) under thousands of
 * routine updates. Call sites opt in.
 */
class AuditLogger
{
    public function __construct(private readonly Request $request) {}

    /**
     * @param  array<string, mixed>|null  $old
     * @param  array<string, mixed>|null  $new
     */
    public function record(
        string $action,
        ?Model $subject = null,
        ?array $old = null,
        ?array $new = null,
        ?int $merchantId = null,
    ): AuditLog {
        $log = new AuditLog;

        $log->forceFill([
            'merchant_id' => $merchantId,
            'user_id' => $this->request->user()?->id,
            'action' => $action,
            'auditable_type' => $subject !== null ? $subject::class : null,
            'auditable_id' => $subject?->getKey(),
            'old_values' => $old,
            'new_values' => $new,
            // Hashed, never raw — an audit trail should not become a log of
            // where staff live.
            'ip_hash' => $this->request->ip() !== null
                ? hash('sha256', $this->request->ip())
                : null,
            'user_agent' => substr((string) $this->request->userAgent(), 0, 512),
        ])->save();

        return $log;
    }
}

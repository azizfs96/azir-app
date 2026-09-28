<?php

namespace App\Domain\Notification\Fcm;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Firebase Cloud Messaging over the HTTP v1 API (spec §23).
 *
 * Authentication is a service-account JWT exchanged for a short-lived OAuth
 * token — the same flow the Firebase Admin SDK runs, implemented directly so
 * the platform carries no extra dependency. The access token is cached until
 * just before it expires so a burst of notifications makes one token call.
 *
 * Intentionally NOT a Laravel Notification channel wrapper: the platform keeps
 * one uniform pipeline (NotificationDispatcher) across push, SMS and WhatsApp.
 */
class FcmClient
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    /** @var array<string, mixed>|null */
    private ?array $credentials = null;

    public function __construct(private readonly ?string $credentialsPath, private readonly ?string $projectId) {}

    /** Whether the channel is configured at all (file present and readable). */
    public function isConfigured(): bool
    {
        return $this->credentialsPath !== null && is_file($this->credentialsPath);
    }

    /**
     * Push one message to one device token.
     *
     * @param  array<string, mixed>  $data
     * @return FcmResult  sent, or unregistered (caller should prune the token), or failed
     */
    public function send(string $deviceToken, string $title, string $body, array $data = []): FcmResult
    {
        $projectId = $this->projectId();

        $response = Http::withToken($this->accessToken())
            ->acceptJson()
            ->post("https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send", [
                'message' => [
                    'token' => $deviceToken,
                    'notification' => ['title' => $title, 'body' => $body],
                    // FCM data values must all be strings.
                    'data' => array_map(static fn ($v) => (string) $v, $data),
                    'apns' => [
                        'payload' => ['aps' => ['sound' => 'default', 'badge' => 1]],
                    ],
                ],
            ]);

        if ($response->successful()) {
            return FcmResult::Sent;
        }

        // A token that Apple/Firebase no longer recognises: tell the caller to
        // drop it so we stop pushing into the void (spec §23).
        $status = $response->json('error.status');
        if (in_array($status, ['NOT_FOUND', 'UNREGISTERED', 'INVALID_ARGUMENT'], true) || $response->status() === 404) {
            return FcmResult::Unregistered;
        }

        throw new RuntimeException('FCM send failed: '.$response->status().' '.$response->body());
    }

    private function projectId(): string
    {
        return $this->projectId ?: (string) ($this->credentials()['project_id'] ?? '');
    }

    /**
     * A cached OAuth access token for the messaging scope. Cached ~55 min; the
     * token itself lives 60, so we never present an expired one.
     */
    private function accessToken(): string
    {
        return Cache::remember('fcm.access_token', now()->addMinutes(55), function (): string {
            $creds = $this->credentials();
            $now = time();

            $jwt = $this->encodeJwt([
                'iss' => $creds['client_email'],
                'scope' => self::SCOPE,
                'aud' => $creds['token_uri'] ?? 'https://oauth2.googleapis.com/token',
                'iat' => $now,
                'exp' => $now + 3600,
            ], $creds['private_key']);

            $response = Http::asForm()->post($creds['token_uri'] ?? 'https://oauth2.googleapis.com/token', [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ]);

            if (! $response->successful()) {
                throw new RuntimeException('FCM token exchange failed: '.$response->status().' '.$response->body());
            }

            return (string) $response->json('access_token');
        });
    }

    /**
     * @param  array<string, mixed>  $claims
     */
    private function encodeJwt(array $claims, string $privateKey): string
    {
        $segments = [
            $this->base64Url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR)),
            $this->base64Url(json_encode($claims, JSON_THROW_ON_ERROR)),
        ];

        $signingInput = implode('.', $segments);
        $signature = '';

        if (! openssl_sign($signingInput, $signature, $privateKey, OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('FCM JWT signing failed (bad service-account private key).');
        }

        $segments[] = $this->base64Url($signature);

        return implode('.', $segments);
    }

    private function base64Url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    /**
     * @return array<string, mixed>
     */
    private function credentials(): array
    {
        if ($this->credentials !== null) {
            return $this->credentials;
        }

        if (! $this->isConfigured()) {
            throw new RuntimeException('FCM credentials file not found at: '.$this->credentialsPath);
        }

        $decoded = json_decode((string) file_get_contents($this->credentialsPath), true);

        if (! is_array($decoded) || ! isset($decoded['client_email'], $decoded['private_key'])) {
            throw new RuntimeException('FCM credentials file is not a valid service account JSON.');
        }

        return $this->credentials = $decoded;
    }
}

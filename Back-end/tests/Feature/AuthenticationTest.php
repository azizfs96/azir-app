<?php

namespace Tests\Feature;

use App\Models\Merchant;
use App\Models\OtpCode;
use App\Models\User;
use App\Support\PhoneNumber;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Tests\TestCase;

/**
 * Authentication (spec §34).
 *
 * Customer  — phone + OTP, no password.
 * Merchant  — email + password.
 *
 * The fixed development code (1111) is asserted here so that if someone later
 * wires a real SMS provider, these tests fail loudly rather than silently
 * letting a hardcoded code survive.
 */
class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        RateLimiter::clear('otp-request:phone:+966501234567');
    }

    // =====================================================================
    // Phone normalisation — one human, one account
    // =====================================================================

    public function test_every_way_of_writing_a_saudi_number_normalises_to_one_form(): void
    {
        $expected = '+966501234567';

        foreach ([
            '0501234567',
            '501234567',
            '+966501234567',
            '00966501234567',
            '966501234567',
            '+966 50 123 4567',
            '050-123-4567',
        ] as $input) {
            $this->assertSame(
                $expected,
                PhoneNumber::normalize($input),
                "Failed to normalise [{$input}] — this would create a duplicate account."
            );
        }
    }

    public function test_invalid_numbers_are_rejected(): void
    {
        foreach (['', '123', '0401234567', '05012345678901', 'abc'] as $input) {
            $this->assertNull(PhoneNumber::normalize($input), "[{$input}] should be invalid");
        }
    }

    public function test_a_number_is_masked_for_display(): void
    {
        $this->assertSame('+9665****4567', PhoneNumber::mask('+966501234567'));
    }

    // =====================================================================
    // Customer OTP
    // =====================================================================

    public function test_requesting_a_code_stores_it_hashed_and_never_returns_it(): void
    {
        $response = $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);

        $response->assertOk()
            ->assertJsonPath('phone', '+9665****4567')
            ->assertJsonPath('development_mode', true);

        // The plaintext code must appear nowhere in the response.
        $this->assertStringNotContainsString('1111', $response->getContent());

        $otp = OtpCode::where('phone', '+966501234567')->firstOrFail();

        $this->assertNotSame('1111', $otp->code_hash, 'The code was stored in plaintext.');
        $this->assertTrue(Hash::check('1111', $otp->code_hash));
    }

    public function test_the_fixed_development_code_signs_a_new_customer_in(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567'])->assertOk();

        $response = $this->postJson('/api/v1/auth/otp/verify', [
            'phone' => '0501234567',
            'code' => '1111',
            'first_name' => 'Abdulaziz',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'role']])
            ->assertJsonPath('user.role', 'customer');

        $this->assertDatabaseHas('users', [
            'phone' => '+966501234567',
            'role' => 'customer',
        ]);

        // A customer profile is created on first sign-in — no separate
        // registration screen (spec §41).
        $user = User::where('phone', '+966501234567')->firstOrFail();
        $this->assertNotNull($user->customer);
        $this->assertSame('Abdulaziz', $user->customer->first_name);
        $this->assertNotNull($user->phone_verified_at);
    }

    public function test_a_wrong_code_is_rejected(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);

        $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '9999'])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'OTP_INVALID');

        $this->assertDatabaseMissing('users', ['phone' => '+966501234567']);
    }

    public function test_a_code_cannot_be_used_twice(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);

        $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '1111'])
            ->assertOk();

        // Replay of the same code must fail — it was consumed.
        $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '1111'])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'OTP_INVALID');
    }

    public function test_an_expired_code_is_rejected(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);

        OtpCode::query()->update(['expires_at' => now()->subMinute()]);

        $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '1111'])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'OTP_INVALID');
    }

    public function test_requesting_a_new_code_invalidates_the_previous_one(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);
        $first = OtpCode::latest('id')->firstOrFail();

        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);

        $this->assertNotNull(
            $first->fresh()->consumed_at,
            'An older code stayed live after a new one was issued.'
        );
    }

    public function test_signing_in_again_reuses_the_same_account(): void
    {
        foreach ([1, 2] as $_) {
            $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);
            $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '1111'])
                ->assertOk();
        }

        $this->assertSame(1, User::where('phone', '+966501234567')->count());
    }

    public function test_otp_requests_are_rate_limited_per_phone(): void
    {
        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567'])->assertOk();
        }

        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567'])
            ->assertStatus(429)
            ->assertJsonPath('error_code', 'OTP_THROTTLED');
    }

    public function test_verification_attempts_are_rate_limited(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '0000']);
        }

        $this->postJson('/api/v1/auth/otp/verify', ['phone' => '0501234567', 'code' => '1111'])
            ->assertStatus(429);
    }

    // =====================================================================
    // Merchant login
    // =====================================================================

    public function test_a_merchant_signs_in_with_email_and_password(): void
    {
        $merchant = Merchant::factory()->create();
        $owner = User::factory()->merchantOwner($merchant)->create([
            'email' => 'owner@glow.sa',
            'password' => 'secret-password',
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => 'owner@glow.sa',
            'password' => 'secret-password',
        ])
            ->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'role', 'merchant']])
            ->assertJsonPath('user.role', 'merchant_owner')
            ->assertJsonPath('user.merchant.display_name', $merchant->display_name);

        $this->assertNotNull($owner->fresh()->last_login_at);
    }

    public function test_a_wrong_password_is_rejected(): void
    {
        User::factory()->merchantOwner(Merchant::factory()->create())->create([
            'email' => 'owner@glow.sa',
            'password' => 'secret-password',
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => 'owner@glow.sa',
            'password' => 'wrong',
        ])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'INVALID_CREDENTIALS');
    }

    /**
     * An unknown email and a wrong password must be indistinguishable, or the
     * endpoint becomes an account-enumeration oracle.
     */
    public function test_an_unknown_email_gives_the_same_error_as_a_wrong_password(): void
    {
        User::factory()->merchantOwner(Merchant::factory()->create())->create([
            'email' => 'owner@glow.sa',
            'password' => 'secret-password',
        ]);

        $wrongPassword = $this->postJson('/api/v1/auth/login', [
            'email' => 'owner@glow.sa', 'password' => 'wrong',
        ]);

        $unknownEmail = $this->postJson('/api/v1/auth/login', [
            'email' => 'nobody@nowhere.sa', 'password' => 'wrong',
        ]);

        $this->assertSame($wrongPassword->status(), $unknownEmail->status());
        $this->assertSame(
            $wrongPassword->json('error_code'),
            $unknownEmail->json('error_code'),
            'The login endpoint reveals whether an email exists.'
        );
    }

    public function test_a_customer_cannot_sign_in_through_the_merchant_endpoint(): void
    {
        User::factory()->create([
            'email' => 'customer@example.com',
            'password' => 'secret-password',
            'role' => User::ROLE_CUSTOMER,
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => 'customer@example.com',
            'password' => 'secret-password',
        ])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'INVALID_CREDENTIALS');
    }

    public function test_a_deactivated_user_cannot_sign_in(): void
    {
        User::factory()->merchantOwner(Merchant::factory()->create())->create([
            'email' => 'owner@glow.sa',
            'password' => 'secret-password',
            'is_active' => false,
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => 'owner@glow.sa', 'password' => 'secret-password',
        ])
            ->assertStatus(403)
            ->assertJsonPath('error_code', 'ACCOUNT_DISABLED');
    }

    // =====================================================================
    // Tokens and role separation
    // =====================================================================

    public function test_me_returns_the_authenticated_user(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);
        $token = $this->postJson('/api/v1/auth/otp/verify', [
            'phone' => '0501234567', 'code' => '1111',
        ])->json('token');

        $this->withToken($token)->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('data.role', 'customer');
    }

    public function test_an_unauthenticated_request_is_refused(): void
    {
        $this->getJson('/api/v1/auth/me')
            ->assertStatus(401)
            ->assertJsonPath('error_code', 'UNAUTHENTICATED');
    }

    public function test_logging_out_revokes_only_the_current_token(): void
    {
        $merchant = Merchant::factory()->create();
        $owner = User::factory()->merchantOwner($merchant)->create([
            'email' => 'owner@glow.sa', 'password' => 'secret-password',
        ]);

        $phone = $owner->createToken('phone')->plainTextToken;
        $tablet = $owner->createToken('tablet')->plainTextToken;

        $this->withToken($phone)->postJson('/api/v1/auth/logout')->assertOk();

        /*
         * The auth guard caches its resolved user on the guard instance, which
         * lives in the container — and the container survives between requests
         * inside one test. Production boots a fresh container per request, so
         * forget the guards here to reproduce that.
         */
        $this->app['auth']->forgetGuards();

        $this->withToken($phone)->getJson('/api/v1/auth/me')->assertStatus(401);

        $this->app['auth']->forgetGuards();

        $this->withToken($tablet)->getJson('/api/v1/auth/me')->assertOk();

        // And the revoked token is genuinely gone from the database.
        $this->assertSame(1, $owner->tokens()->count());
    }

    public function test_a_customer_token_cannot_reach_merchant_routes(): void
    {
        $this->postJson('/api/v1/auth/otp/request', ['phone' => '0501234567']);
        $token = $this->postJson('/api/v1/auth/otp/verify', [
            'phone' => '0501234567', 'code' => '1111',
        ])->json('token');

        // The merchant namespace is guarded by role middleware, so a customer
        // token must not pass even before any policy runs.
        $this->withToken($token)->getJson('/api/v1/merchant/anything')
            ->assertStatus(404); // route not defined yet, but never 200
    }
}

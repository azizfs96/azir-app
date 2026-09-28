<?php

namespace Tests\Feature;

use App\Domain\Notification\Channels\FcmPushChannel;
use App\Domain\Notification\Fcm\FcmClient;
use App\Models\Customer;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The Firebase push channel (spec §23): sends to every registered device over
 * FCM HTTP v1, and prunes a token FCM reports as dead. No live calls — the
 * token exchange and send endpoints are faked.
 */
class FcmPushChannelTest extends TestCase
{
    use RefreshDatabase;

    private string $credsPath;

    protected function setUp(): void
    {
        parent::setUp();

        // A throwaway service account with a REAL RSA key, so the JWT the client
        // signs is well-formed (openssl_sign needs a valid key).
        $res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
        openssl_pkey_export($res, $privateKey);

        $this->credsPath = tempnam(sys_get_temp_dir(), 'fcm').'.json';
        file_put_contents($this->credsPath, json_encode([
            'type' => 'service_account',
            'project_id' => 'azir-test',
            'private_key' => $privateKey,
            'client_email' => 'fcm@azir-test.iam.gserviceaccount.com',
            'token_uri' => 'https://oauth2.googleapis.com/token',
        ]));
    }

    protected function tearDown(): void
    {
        @unlink($this->credsPath);
        parent::tearDown();
    }

    private function channel(): FcmPushChannel
    {
        return new FcmPushChannel(new FcmClient($this->credsPath, null));
    }

    private function userWithDevice(string $token = 'device-1'): User
    {
        $user = User::factory()->create(['role' => 'customer']);
        Customer::factory()->create(['user_id' => $user->id]);
        $user->deviceTokens()->create(['token' => $token, 'platform' => 'ios']);

        return $user->fresh();
    }

    public function test_it_sends_to_the_registered_device(): void
    {
        Http::fake([
            'oauth2.googleapis.com/token' => Http::response(['access_token' => 'ya29.fake', 'expires_in' => 3600]),
            'fcm.googleapis.com/*' => Http::response(['name' => 'projects/azir-test/messages/1']),
        ]);

        $this->channel()->send($this->userWithDevice(), 'طلبك جاهز', 'تفضّل', ['order_id' => 42]);

        Http::assertSent(fn ($req) => str_contains($req->url(), 'projects/azir-test/messages:send')
            && $req['message']['token'] === 'device-1'
            && $req['message']['notification']['title'] === 'طلبك جاهز'
            && $req['message']['data']['order_id'] === '42'
            && $req['message']['data']['type'] === 'order');
    }

    public function test_it_prunes_a_token_firebase_reports_as_unregistered(): void
    {
        Http::fake([
            'oauth2.googleapis.com/token' => Http::response(['access_token' => 'ya29.fake', 'expires_in' => 3600]),
            'fcm.googleapis.com/*' => Http::response(['error' => ['status' => 'UNREGISTERED']], 404),
        ]);

        $user = $this->userWithDevice('dead-token');

        $this->channel()->send($user, 'x', 'y', []);

        $this->assertDatabaseMissing('device_tokens', ['token' => 'dead-token']);
    }

    public function test_no_devices_means_no_call(): void
    {
        Http::fake();

        $user = User::factory()->create(['role' => 'customer']);
        Customer::factory()->create(['user_id' => $user->id]);

        $this->channel()->send($user->fresh(), 'x', 'y', []);

        Http::assertNothingSent();
    }
}

<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\WaslaNotification;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The customer's in-app inbox: their own in_app notifications, rendered, newest
 * first, with an unread count and a mark-as-read action.
 */
class CustomerNotificationTest extends TestCase
{
    use RefreshDatabase;

    private function customer(): User
    {
        $user = User::factory()->create(['role' => 'customer']);
        \App\Models\Customer::factory()->create(['user_id' => $user->id]);

        return $user->fresh();
    }

    private function notify(User $user, string $channel = 'in_app'): WaslaNotification
    {
        $n = new WaslaNotification;
        $n->forceFill([
            'notifiable_type' => User::class,
            'notifiable_id' => $user->id,
            'channel' => $channel,
            'template_key' => 'booking_confirmed',
            'payload' => ['store_name' => 'برجر بلد', 'date' => 'الأحد', 'time' => '٥:٠٠'],
            'locale' => 'ar',
            'status' => 'sent',
            'sent_at' => CarbonImmutable::now(),
        ])->save();

        return $n;
    }

    public function test_the_inbox_returns_the_customers_in_app_notifications(): void
    {
        $user = $this->customer();
        $this->notify($user);
        $this->notify($user, 'push'); // not in-app — must be excluded

        $this->actingAs($user)->getJson('/api/v1/me/notifications')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('unread', 1)
            ->assertJsonPath('data.0.title', 'تم تأكيد الحجز');
    }

    public function test_a_customer_sees_only_their_own_notifications(): void
    {
        $mine = $this->customer();
        $other = $this->customer();
        $this->notify($other);

        $this->actingAs($mine)->getJson('/api/v1/me/notifications')
            ->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_marking_read_clears_the_unread_flag(): void
    {
        $user = $this->customer();
        $n = $this->notify($user);

        $this->actingAs($user)->postJson("/api/v1/me/notifications/{$n->id}/read")->assertNoContent();

        $this->actingAs($user)->getJson('/api/v1/me/notifications')
            ->assertOk()->assertJsonPath('unread', 0)->assertJsonPath('data.0.is_read', true);
    }
}

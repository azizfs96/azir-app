<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingStatus;
use App\Domain\Booking\Events\BookingStatusChanged;
use App\Models\Booking;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Store;
use App\Models\User;
use App\Models\WaslaNotification;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;

/**
 * Notifications (spec §23).
 *
 * The point of these tests is the SEAM: the booking engine emits events and
 * knows nothing about delivery, so SMS and WhatsApp can be added later without
 * touching booking code.
 */
class NotificationTest extends TestCase
{
    use RefreshDatabase;

    private Store $store;

    private Customer $customer;

    private Service $service;

    private Branch $branch;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $merchant->id,
            'name_en' => 'Glow Beauty',
        ]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'reminder_hours_before' => 24,
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create();
        $this->service = Service::factory()->forStore($this->store)->create([
            'name_en' => 'Hair Color', 'duration_minutes' => 60,
        ]);

        $user = User::factory()->customer()->create(['locale' => 'en']);
        $this->customer = Customer::create(['user_id' => $user->id, 'first_name' => 'Abdulaziz']);
        $user->deviceTokens()->create(['token' => 'device-abc', 'platform' => 'ios']);
    }

    private function makeBooking(?CarbonImmutable $startsAt = null): Booking
    {
        $startsAt ??= CarbonImmutable::now()->addDays(3);

        $booking = new Booking([
            'store_id' => $this->store->id,
            'branch_id' => $this->branch->id,
            'customer_id' => $this->customer->id,
            'service_id' => $this->service->id,
            'starts_at' => $startsAt,
            'ends_at' => $startsAt->addHour(),
            'duration_minutes' => 60,
            'price' => 250,
        ]);

        $booking->forceFill(['merchant_id' => $this->store->merchant_id])->save();

        return $booking;
    }

    // =====================================================================
    // The seam
    // =====================================================================

    public function test_a_status_change_emits_a_domain_event(): void
    {
        Event::fake([BookingStatusChanged::class]);

        $booking = $this->makeBooking();
        $booking->transitionTo(BookingStatus::Confirmed, 'system');

        Event::assertDispatched(
            BookingStatusChanged::class,
            fn (BookingStatusChanged $e) => $e->to === BookingStatus::Confirmed
                && $e->from === BookingStatus::Pending
                && $e->booking->is($booking),
        );
    }

    // =====================================================================
    // Delivery
    // =====================================================================

    public function test_confirming_a_booking_notifies_the_customer_on_every_channel(): void
    {
        $booking = $this->makeBooking();
        $booking->transitionTo(BookingStatus::Confirmed, 'system');

        $notifications = WaslaNotification::where('booking_id', $booking->id)->get();

        // In-app inbox + push.
        $this->assertCount(2, $notifications);
        $this->assertEqualsCanonicalizing(
            ['in_app', 'push'],
            $notifications->pluck('channel')->all(),
        );

        foreach ($notifications as $notification) {
            $this->assertSame('booking_confirmed', $notification->template_key);
            $this->assertSame('sent', $notification->status);
            $this->assertNotNull($notification->sent_at);
        }
    }

    /**
     * Stored as template_key + payload, never a rendered string — so the same
     * record can render in Arabic or English (spec §33).
     */
    public function test_the_record_stores_data_not_a_rendered_sentence(): void
    {
        $booking = $this->makeBooking();
        $booking->transitionTo(BookingStatus::Confirmed, 'system');

        $notification = WaslaNotification::where('booking_id', $booking->id)->firstOrFail();

        $this->assertSame('booking_confirmed', $notification->template_key);
        $this->assertSame('Glow Beauty', $notification->payload['store_name']);
        $this->assertSame($booking->reference, $notification->payload['reference']);
        $this->assertSame('en', $notification->locale);
    }

    public function test_the_customers_locale_decides_the_language(): void
    {
        $this->customer->user->forceFill(['locale' => 'ar'])->save();

        $booking = $this->makeBooking();
        $booking->transitionTo(BookingStatus::Confirmed, 'system');

        $notification = WaslaNotification::where('booking_id', $booking->id)->firstOrFail();

        $this->assertSame('ar', $notification->locale);
        // The Arabic store name, not the English one.
        $this->assertSame($this->store->name_ar, $notification->payload['store_name']);
    }

    public function test_cancelling_notifies_the_customer(): void
    {
        $booking = $this->makeBooking();
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        WaslaNotification::query()->delete();

        $booking->transitionTo(BookingStatus::Cancelled, 'merchant');

        $this->assertSame(
            'booking_cancelled',
            WaslaNotification::firstOrFail()->template_key,
        );
    }

    /**
     * Notifying on every transition would train people to ignore Wasla.
     */
    public function test_uninteresting_transitions_are_silent(): void
    {
        $booking = $this->makeBooking();
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        WaslaNotification::query()->delete();

        $booking->transitionTo(BookingStatus::CheckedIn, 'merchant');

        $this->assertSame(0, WaslaNotification::count(), 'check-in should not notify');
    }

    public function test_a_guest_booking_notifies_nobody(): void
    {
        $booking = new Booking([
            'store_id' => $this->store->id,
            'branch_id' => $this->branch->id,
            'service_id' => $this->service->id,
            'guest_name' => 'Walk-in',
            'guest_phone' => '+966501234567',
            'starts_at' => CarbonImmutable::now()->addDay(),
            'ends_at' => CarbonImmutable::now()->addDay()->addHour(),
            'duration_minutes' => 60,
            'price' => 100,
        ]);
        $booking->forceFill(['merchant_id' => $this->store->merchant_id])->save();

        // No account means no push target. SMS would cover this once a provider
        // is chosen — until then it must not explode.
        $booking->transitionTo(BookingStatus::Confirmed, 'system');

        $this->assertSame(0, WaslaNotification::count());
    }

    // =====================================================================
    // Reminders (spec §23)
    // =====================================================================

    public function test_a_reminder_is_sent_inside_the_stores_window(): void
    {
        // 12 hours away, store reminds at 24 — due.
        $booking = $this->makeBooking(CarbonImmutable::now()->addHours(12));
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        WaslaNotification::query()->delete();

        $this->artisan('wasla:send-reminders')->assertSuccessful();

        $this->assertSame(
            'booking_reminder',
            WaslaNotification::firstOrFail()->template_key,
        );
        $this->assertNotNull($booking->fresh()->reminder_sent_at);
    }

    public function test_a_reminder_is_not_sent_too_early(): void
    {
        // 5 days away, store reminds at 24 hours — not due.
        $booking = $this->makeBooking(CarbonImmutable::now()->addDays(5));
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        WaslaNotification::query()->delete();

        $this->artisan('wasla:send-reminders')->assertSuccessful();

        $this->assertSame(0, WaslaNotification::count());
        $this->assertNull($booking->fresh()->reminder_sent_at);
    }

    /**
     * The command runs every 15 minutes, so it MUST be idempotent.
     */
    public function test_a_reminder_is_never_sent_twice(): void
    {
        $booking = $this->makeBooking(CarbonImmutable::now()->addHours(12));
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        WaslaNotification::query()->delete();

        $this->artisan('wasla:send-reminders');
        $this->artisan('wasla:send-reminders');
        $this->artisan('wasla:send-reminders');

        // One record per channel is expected; the guarantee is that repeated
        // runs do not add MORE. Two channels x one reminder = 2.
        $this->assertSame(2, WaslaNotification::where('template_key', 'booking_reminder')->count());
    }

    public function test_a_cancelled_booking_is_never_reminded(): void
    {
        $booking = $this->makeBooking(CarbonImmutable::now()->addHours(12));
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        $booking->transitionTo(BookingStatus::Cancelled, 'customer');
        WaslaNotification::query()->delete();

        $this->artisan('wasla:send-reminders')->assertSuccessful();

        $this->assertSame(0, WaslaNotification::count());
    }

    public function test_each_store_uses_its_own_reminder_window(): void
    {
        // This store reminds only 2 hours ahead.
        $this->store->bookingSettings->update(['reminder_hours_before' => 2]);

        $booking = $this->makeBooking(CarbonImmutable::now()->addHours(12));
        $booking->transitionTo(BookingStatus::Confirmed, 'system');
        WaslaNotification::query()->delete();

        $this->artisan('wasla:send-reminders')->assertSuccessful();

        $this->assertSame(0, WaslaNotification::count(), '12h out should not trigger a 2h reminder');
    }
}

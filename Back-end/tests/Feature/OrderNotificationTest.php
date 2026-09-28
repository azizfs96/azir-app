<?php

namespace Tests\Feature;

use App\Domain\Ordering\OrderService;
use App\Domain\Ordering\OrderStatus;
use App\Models\Branch;
use App\Models\BookingSettings;
use App\Models\Customer;
use App\Models\Merchant;
use App\Models\MenuItem;
use App\Models\Store;
use App\Models\User;
use App\Models\WaslaNotification;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Order lifecycle -> customer inbox (spec §23). An order status change lands in
 * the same in-app inbox as bookings, rendered in the reader's locale.
 */
class OrderNotificationTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchant;

    private Store $store;

    private MenuItem $burger;

    protected function setUp(): void
    {
        parent::setUp();

        $this->merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $this->merchant->id,
            'business_type' => 'restaurant',
        ]);
        BookingSettings::create(array_merge(
            BookingSettings::defaults(),
            ['store_id' => $this->store->id],
        ));
        Branch::factory()->forStore($this->store)->create();

        $this->burger = MenuItem::create([
            'store_id' => $this->store->id,
            'name_ar' => 'برجر', 'price' => 30,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    private function freshStore(): Store
    {
        return Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id);
    }

    private function customerWithUser(): Customer
    {
        $user = User::factory()->create(['role' => 'customer', 'locale' => 'ar']);

        return Customer::factory()->create(['user_id' => $user->id]);
    }

    private function place(Customer $customer)
    {
        return app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'pickup',
            customer: $customer,
        );
    }

    public function test_accepting_an_order_notifies_the_customer(): void
    {
        $customer = $this->customerWithUser();
        $order = $this->place($customer);

        // Placing alone is not a notification — the customer is on the tracker.
        $this->assertDatabaseMissing('wasla_notifications', [
            'order_id' => $order->id,
            'channel' => 'in_app',
        ]);

        $order->transitionTo(OrderStatus::Accepted, 'merchant');

        $inbox = WaslaNotification::query()
            ->where('order_id', $order->id)->where('channel', 'in_app')->first();

        $this->assertNotNull($inbox);
        $this->assertSame('order_accepted', $inbox->template_key);
        $this->assertSame($customer->user_id, $inbox->notifiable_id);
        $this->assertSame('تم قبول طلبك', $inbox->render('ar')['title']);
    }

    public function test_ready_and_completed_each_notify(): void
    {
        $customer = $this->customerWithUser();
        $order = $this->place($customer);

        $order->transitionTo(OrderStatus::Accepted, 'merchant');
        $order->transitionTo(OrderStatus::Ready, 'merchant');
        $order->transitionTo(OrderStatus::Completed, 'merchant');

        $keys = WaslaNotification::query()
            ->where('order_id', $order->id)->where('channel', 'in_app')
            ->pluck('template_key')->all();

        $this->assertContains('order_accepted', $keys);
        $this->assertContains('order_ready', $keys);
        $this->assertContains('order_completed', $keys);
    }

    public function test_a_customers_own_cancel_does_not_notify_them(): void
    {
        $customer = $this->customerWithUser();
        $order = $this->place($customer);

        $order->transitionTo(OrderStatus::Cancelled, 'customer');

        $this->assertDatabaseMissing('wasla_notifications', [
            'order_id' => $order->id,
            'template_key' => 'order_cancelled',
        ]);
    }

    public function test_a_guest_order_notifies_no_one(): void
    {
        $order = app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );

        $order->transitionTo(OrderStatus::Accepted, 'merchant');

        $this->assertDatabaseMissing('wasla_notifications', ['order_id' => $order->id]);
    }
}

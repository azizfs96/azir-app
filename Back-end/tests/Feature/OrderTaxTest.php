<?php

namespace Tests\Feature;

use App\Domain\Ordering\OrderService;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\MenuItem;
use App\Models\Store;
use App\Support\TenantContext;
use App\Support\ZatcaQr;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * VAT (spec §35): off by default, added on top when enabled, and the seller's
 * details are snapshotted onto the order so the ZATCA QR reflects the terms in
 * force when the invoice was issued.
 */
class OrderTaxTest extends TestCase
{
    use RefreshDatabase;

    private Store $store;

    private MenuItem $burger;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $merchant->id,
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

    private function enableTax(): void
    {
        $this->store->bookingSettings->update([
            'tax_enabled' => true,
            'tax_rate' => 15,
            'tax_number' => '300000000000003',
            'legal_name' => 'مؤسسة برجر البلد',
            'national_address' => 'الرياض 12345',
        ]);
    }

    private function place()
    {
        return app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );
    }

    public function test_tax_is_off_by_default(): void
    {
        $order = $this->place();

        $this->assertSame(0.0, (float) $order->tax_amount);
        $this->assertSame(30.0, (float) $order->total);
    }

    public function test_enabled_tax_is_added_on_top_and_snapshotted(): void
    {
        $this->enableTax();
        $order = $this->place();

        // 30 × 15% = 4.50, total 34.50.
        $this->assertSame(15.0, (float) $order->tax_rate);
        $this->assertSame(4.5, (float) $order->tax_amount);
        $this->assertSame(34.5, (float) $order->total);
        $this->assertSame('مؤسسة برجر البلد', $order->seller_name);
        $this->assertSame('300000000000003', $order->tax_number);
        $this->assertSame('الرياض 12345', $order->national_address);
    }

    public function test_the_zatca_qr_encodes_the_five_tlv_fields(): void
    {
        $this->enableTax();
        $order = $this->place();

        $qr = ZatcaQr::forOrder($order);
        $this->assertNotNull($qr);

        $tlv = base64_decode($qr);

        // Walk the TLV and pull out the five values.
        $fields = [];
        $i = 0;
        while ($i < strlen($tlv)) {
            $tag = ord($tlv[$i]);
            $len = ord($tlv[$i + 1]);
            $fields[$tag] = substr($tlv, $i + 2, $len);
            $i += 2 + $len;
        }

        $this->assertSame('مؤسسة برجر البلد', $fields[1]);
        $this->assertSame('300000000000003', $fields[2]);
        $this->assertSame('34.50', $fields[4]); // total with VAT
        $this->assertSame('4.50', $fields[5]);  // VAT total
    }

    public function test_no_qr_without_a_vat_number(): void
    {
        $this->store->bookingSettings->update(['tax_enabled' => true, 'tax_rate' => 15]);
        $order = $this->place();

        // Taxed, but with no VAT number there is no compliant invoice to stamp.
        $this->assertNull(ZatcaQr::forOrder($order));
    }
}

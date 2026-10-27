<?php

namespace Tests\Unit;

use App\Support\MapsLink;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MapsLinkTest extends TestCase
{
    public function test_long_links_parse_without_network(): void
    {
        Http::fake();

        $this->assertSame([24.7136, 46.6753], MapsLink::resolve('https://www.google.com/maps/place/X/@24.7136,46.6753,17z/data=!4m5'));
        $this->assertSame([24.7136, 46.6753], MapsLink::resolve('https://maps.google.com/?q=24.7136,46.6753'));
        $this->assertSame([24.7136, 46.6753], MapsLink::resolve('https://www.google.com/maps/place/X/data=!3m1!4b1!4m6!3m5!1s0x0!8m2!3d24.7136!4d46.6753'));
        $this->assertSame([24.7136, 46.6753], MapsLink::resolve('24.7136, 46.6753'));
        Http::assertNothingSent();
    }

    public function test_short_links_follow_the_redirect(): void
    {
        Http::fake([
            'maps.app.goo.gl/*' => Http::response('<html></html>', 200, [
                'X-Guzzle-Redirect-History' => 'https://www.google.com/maps/place/Cafe/@24.7743,46.683,17z/data=!4m2',
            ]),
        ]);

        $this->assertSame([24.7743, 46.683], MapsLink::resolve('https://maps.app.goo.gl/AbCdEf'));
    }

    public function test_place_page_body_is_searched_when_the_url_has_no_pin(): void
    {
        Http::fake([
            'maps.app.goo.gl/*' => Http::response('…"center":[]…!3d24.8120!4d46.7580…', 200),
        ]);

        $this->assertSame([24.812, 46.758], MapsLink::resolve('https://maps.app.goo.gl/XyZ'));
    }

    public function test_unrelated_hosts_and_junk_return_null(): void
    {
        Http::fake();

        $this->assertNull(MapsLink::resolve('https://example.com/shop'));
        $this->assertNull(MapsLink::resolve(null));
        $this->assertNull(MapsLink::parse('https://www.google.com/maps/@0.0,0.0,2z'));
        Http::assertNothingSent();
    }
}

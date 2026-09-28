<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Merchant;
use App\Models\Store;
use App\Models\User;
use App\Support\ImageOptimizer;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * ============================================================================
 * UPLOADS ARE SHRUNK AT THE DOOR
 *
 * Merchants upload camera originals; customers then download and DECODE them
 * on phones — the storefront-open freeze traced to exactly that. Covers cap at
 * 1600px, logos at 512px; anything unprocessable is stored untouched, because
 * a heavy image beats a failed upload.
 * ============================================================================
 */
class MediaOptimizationTest extends TestCase
{
    use RefreshDatabase;

    private Store $store;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create(['merchant_id' => $merchant->id]);
        Branch::factory()->forStore($this->store)->create();

        $this->owner = User::factory()->create([
            'role' => 'merchant_owner', 'merchant_id' => $merchant->id,
        ]);

        app(TenantContext::class)->setTenant(null);
        Storage::fake('public');
    }

    /**
     * A real PNG at the requested size. PNG, not JPEG, on purpose: the
     * project's static dev PHP ships GD WITHOUT the JPEG codec, and these
     * dimension assertions must hold on every machine. JPEG behaviour on
     * a codec-less build is covered by the passthrough test below.
     */
    private function png(int $width, int $height): UploadedFile
    {
        $image = imagecreatetruecolor($width, $height);
        imagefilledrectangle($image, 0, 0, $width, $height, imagecolorallocate($image, 200, 60, 90));

        ob_start();
        imagepng($image);
        $binary = ob_get_clean();
        imagedestroy($image);

        $path = tempnam(sys_get_temp_dir(), 'img').'.png';
        file_put_contents($path, $binary);

        return new UploadedFile($path, 'photo.png', 'image/png', null, true);
    }

    private function storedDimensions(string $path): array
    {
        $info = getimagesizefromstring(Storage::disk('public')->get($path));

        return [$info[0], $info[1]];
    }

    private function asOwner(): static
    {
        $this->actingAs($this->owner);
        app(TenantContext::class)->setTenant(Merchant::find($this->store->merchant_id));

        return $this;
    }

    public function test_an_oversized_cover_is_downscaled_to_1600(): void
    {
        $this->asOwner()->post('/api/v1/merchant/settings/media', [
            'type' => 'cover',
            'file' => $this->png(2400, 1800),
        ])->assertCreated();

        [$width, $height] = $this->storedDimensions($this->store->fresh()->cover_path);

        $this->assertSame(1600, $width, 'The oversized upload was stored at full size.');
        $this->assertSame(1200, $height, 'Aspect ratio was not preserved.');
    }

    public function test_a_logo_is_downscaled_to_512(): void
    {
        $this->asOwner()->post('/api/v1/merchant/settings/media', [
            'type' => 'logo',
            'file' => $this->png(1400, 1400),
        ])->assertCreated();

        [$width, $height] = $this->storedDimensions($this->store->fresh()->logo_path);

        $this->assertSame([512, 512], [$width, $height]);
    }

    public function test_an_already_small_image_is_stored_byte_identical(): void
    {
        $file = $this->png(800, 500);
        $original = $file->getContent();

        $this->asOwner()->post('/api/v1/merchant/settings/media', [
            'type' => 'cover',
            'file' => $file,
        ])->assertCreated();

        $this->assertSame(
            $original,
            Storage::disk('public')->get($this->store->fresh()->cover_path),
            'A small image must pass through untouched — no needless re-encode.',
        );
    }

    public function test_a_jpeg_on_a_codec_less_build_passes_through(): void
    {
        // A minimal valid 1x1 JPEG. On a full GD it is under every cap; on
        // this dev build it cannot even be decoded — either way the bytes
        // must come back untouched with the honest 'jpg' extension.
        $jpeg = base64_decode(
            '/9j/4AAQSkZJRgABAQEAAAAAAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
            .'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
            .'AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AVN//2Q=='
        );

        [$bytes, $extension] = ImageOptimizer::shrink($jpeg, 1600, 'image/jpeg');

        $this->assertSame($jpeg, $bytes);
        $this->assertSame('jpg', $extension);
    }

    public function test_unprocessable_bytes_pass_through_rather_than_failing(): void
    {
        $garbage = random_bytes(4096);

        [$bytes, $extension] = ImageOptimizer::shrink($garbage, 1600, 'image/jpeg');

        $this->assertSame($garbage, $bytes, 'Bytes GD cannot read must pass through.');
        $this->assertSame('jpg', $extension);
    }

    public function test_png_transparency_survives_the_downscale(): void
    {
        // A 1200px transparent PNG logo.
        $image = imagecreatetruecolor(1200, 1200);
        imagealphablending($image, false);
        imagesavealpha($image, true);
        imagefill($image, 0, 0, imagecolorallocatealpha($image, 0, 0, 0, 127));

        ob_start();
        imagepng($image);
        $binary = ob_get_clean();
        imagedestroy($image);

        [$shrunk, $extension] = ImageOptimizer::shrink($binary, 512, 'image/png');
        $this->assertSame('png', $extension);
        $result = imagecreatefromstring($shrunk);

        $this->assertSame(512, imagesx($result));

        // The corner pixel must still be fully transparent.
        $alpha = (imagecolorat($result, 0, 0) & 0x7F000000) >> 24;
        $this->assertSame(127, $alpha, 'Transparency was flattened.');
    }
}

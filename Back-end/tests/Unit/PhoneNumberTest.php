<?php

namespace Tests\Unit;

use App\Support\PhoneNumber;
use PHPUnit\Framework\TestCase;

class PhoneNumberTest extends TestCase
{
    public function test_saudi_formats_normalize_to_e164(): void
    {
        $this->assertSame('+966551234567', PhoneNumber::normalize('0551234567'));
        $this->assertSame('+966551234567', PhoneNumber::normalize('+966 55 123 4567'));
        $this->assertSame('+966551234567', PhoneNumber::normalize('00966551234567'));
        $this->assertSame('+966551234567', PhoneNumber::normalize('551234567'));
    }

    public function test_arabic_and_persian_digits_are_accepted(): void
    {
        // What an Arabic keyboard actually types.
        $this->assertSame('+966551234567', PhoneNumber::normalize('٠٥٥١٢٣٤٥٦٧'));
        $this->assertSame('+966551234567', PhoneNumber::normalize('۰۵۵۱۲۳۴۵۶۷'));
    }

    public function test_non_saudi_mobiles_are_rejected(): void
    {
        $this->assertNull(PhoneNumber::normalize('0112345678'));
        $this->assertNull(PhoneNumber::normalize('12345'));
        $this->assertNull(PhoneNumber::normalize(''));
    }
}

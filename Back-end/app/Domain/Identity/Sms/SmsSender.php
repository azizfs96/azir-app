<?php

namespace App\Domain\Identity\Sms;

/**
 * The SMS boundary (spec §23, §34).
 *
 * Deliberately tiny. When a provider is chosen (Unifonic / Msegat / Taqnyat /
 * Twilio), it is one class implementing this interface plus one config line —
 * no change to OtpService or anything that calls it.
 */
interface SmsSender
{
    /**
     * @param  string  $to  E.164, e.g. +966501234567
     */
    public function send(string $to, string $message): void;
}

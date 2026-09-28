<?php

namespace App\Domain\Identity\Sms;

use App\Support\PhoneNumber;
use Illuminate\Support\Facades\Log;

/**
 * Development driver: writes the message to the log instead of sending it.
 *
 * Lets the whole auth flow be driven end to end with no provider account and no
 * per-message cost. The number is masked even here — logs get shared, pasted
 * into tickets, and shipped to third-party aggregators.
 */
class LogSmsSender implements SmsSender
{
    public function send(string $to, string $message): void
    {
        Log::info('[sms] '.PhoneNumber::mask($to).' :: '.$message);
    }
}

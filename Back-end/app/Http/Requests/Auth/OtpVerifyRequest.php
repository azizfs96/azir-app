<?php

namespace App\Http\Requests\Auth;

use App\Support\PhoneNumber;
use Illuminate\Foundation\Http\FormRequest;

/** POST /auth/otp/verify */
class OtpVerifyRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'phone' => ['required', 'string', 'max:20'],
            'code' => ['required', 'string', 'min:4', 'max:8'],
            // Optional profile capture on first sign-in, so the customer is not
            // sent through a separate onboarding screen (spec §41).
            'first_name' => ['sometimes', 'nullable', 'string', 'max:60'],
            'last_name' => ['sometimes', 'nullable', 'string', 'max:60'],
            'device_token' => ['sometimes', 'nullable', 'string', 'max:512'],
            'platform' => ['sometimes', 'nullable', 'in:ios,android'],
        ];
    }

    public function normalizedPhone(): string
    {
        return PhoneNumber::normalize((string) $this->input('phone')) ?? '';
    }
}

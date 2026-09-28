<?php

namespace App\Http\Requests\Auth;

use App\Support\PhoneNumber;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/** POST /auth/otp/request */
class OtpRequestRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'phone' => ['required', 'string', 'max:20'],
        ];
    }

    /**
     * Normalise before validating so 0501234567 and +966501234567 are the
     * same person (see PhoneNumber).
     */
    public function after(): array
    {
        return [
            function (Validator $validator): void {
                if (PhoneNumber::normalize((string) $this->input('phone')) === null) {
                    $validator->errors()->add('phone', __('auth.invalid_phone'));
                }
            },
        ];
    }

    public function normalizedPhone(): string
    {
        return PhoneNumber::normalize((string) $this->input('phone')) ?? '';
    }
}

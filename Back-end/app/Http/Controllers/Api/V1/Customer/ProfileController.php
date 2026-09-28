<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The signed-in customer's own profile — name and phone for the account screen.
 * Deliberately tiny: Wasla keeps almost nothing about a customer.
 */
class ProfileController extends Controller
{
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        $customer = $user->customer;

        return response()->json([
            'name' => $customer?->fullName() ?? $user->name,
            'phone' => $user->phone,
        ]);
    }
}

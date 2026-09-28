<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\WaslaNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The signed-in customer's in-app inbox (spec §23). Rendered per the reader's
 * locale at read time, newest first.
 */
class NotificationController extends Controller
{
    /** GET /me/notifications */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $locale = app()->getLocale();

        $items = WaslaNotification::query()
            ->inbox()
            ->where('notifiable_type', User::class)
            ->where('notifiable_id', $user->id)
            ->limit(50)
            ->get()
            ->map(function (WaslaNotification $n) use ($locale): array {
                $rendered = $n->render($locale);

                return [
                    'id' => $n->id,
                    'title' => $rendered['title'],
                    'body' => $rendered['body'],
                    'is_read' => $n->read_at !== null,
                    'created_at' => $n->created_at?->toIso8601String(),
                ];
            });

        return response()->json([
            'data' => $items,
            'unread' => $items->where('is_read', false)->count(),
        ]);
    }

    /** POST /me/notifications/{id}/read */
    public function read(int $id, Request $request): JsonResponse
    {
        $n = WaslaNotification::query()
            ->where('notifiable_type', User::class)
            ->where('notifiable_id', $request->user()->id)
            ->find($id);

        if ($n === null) {
            return response()->json(['message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND'], 404);
        }

        $n->markRead();

        return response()->json(null, 204);
    }
}

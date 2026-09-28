<?php

namespace App\Domain\Notification\Fcm;

/** The outcome of a single FCM send (spec §23). */
enum FcmResult
{
    case Sent;
    case Unregistered; // token is dead — prune it
    case Failed;
}

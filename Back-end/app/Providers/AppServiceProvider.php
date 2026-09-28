<?php

namespace App\Providers;

use App\Domain\Booking\Events\BookingRescheduled;
use App\Domain\Booking\Events\BookingStatusChanged;
use App\Domain\Identity\Sms\LogSmsSender;
use App\Domain\Identity\Sms\SmsSender;
use App\Domain\Notification\Channels\FcmPushChannel;
use App\Domain\Notification\Channels\InAppChannel;
use App\Domain\Notification\Fcm\FcmClient;
use App\Domain\Notification\NotificationDispatcher;
use App\Domain\Ordering\Events\OrderStatusChanged;
use App\Listeners\SendBookingNotification;
use App\Listeners\SendOrderNotification;
use App\Models\Booking;
use App\Models\BranchSchedule;
use App\Models\StaffSchedule;
use App\Models\TimeOff;
use App\Observers\BookingAvailabilityObserver;
use App\Observers\ScheduleAvailabilityObserver;
use Illuminate\Support\Facades\Event;
use App\Engines\BusinessEngineRegistry;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        /*
         * Request-scoped tenant. Singleton so ResolveTenant sets it once and
         * every global scope in the request reads the same value
         * (ARCHITECTURE.md §4).
         */
        $this->app->singleton(TenantContext::class);

        $this->app->singleton(BusinessEngineRegistry::class, fn () => new BusinessEngineRegistry(
            config('wasla.engines', []),
            config('wasla.default_engine', 'beauty_wellness'),
        ));

        /*
         * SMS driver (spec §34). 'log' writes the code to the log instead of
         * sending it — enough to drive the whole auth flow with no provider
         * account. Adding Unifonic/Msegat later is one class plus one case.
         */
        $this->app->bind(SmsSender::class, fn () => match (config('wasla.otp.driver')) {
            default => new LogSmsSender,
        });

        /*
         * Notification channels (spec §23).
         *
         * MVP: in-app inbox + push. Push delivers over Firebase (FcmPushChannel)
         * and degrades to a log line when no credentials are present, so dev and
         * tests behave as before. Adding SMS or WhatsApp is one class plus one
         * entry in this array — nothing in the booking engine changes.
         */
        $this->app->singleton(FcmClient::class, fn () => new FcmClient(
            config('services.fcm.credentials'),
            config('services.fcm.project_id'),
        ));

        $this->app->singleton(NotificationDispatcher::class, fn ($app) => new NotificationDispatcher([
            new InAppChannel,
            new FcmPushChannel($app->make(FcmClient::class)),
        ]));
    }

    public function boot(): void
    {
        /*
         * CarbonImmutable everywhere. Availability maths does a lot of
         * ->addMinutes() on shared values; mutable Carbon makes that a source
         * of very subtle scheduling bugs (ARCHITECTURE.md §6).
         */
        Date::use(\Carbon\CarbonImmutable::class);

        /*
         * Fail loudly in development:
         *  - preventLazyLoading catches N+1s in the availability engine, where
         *    they are the difference between 150ms and 15s.
         *  - preventSilentlyDiscardingAttributes catches a fill() with a key
         *    that is not fillable, instead of quietly dropping it.
         */
        Model::preventLazyLoading(! $this->app->isProduction());
        Model::preventSilentlyDiscardingAttributes(! $this->app->isProduction());

        // Booking lifecycle -> notifications (spec §23).
        Event::listen(BookingStatusChanged::class, [SendBookingNotification::class, 'onStatusChanged']);
        Event::listen(BookingRescheduled::class, [SendBookingNotification::class, 'onRescheduled']);

        // Order lifecycle -> notifications (spec §23).
        Event::listen(OrderStatusChanged::class, [SendOrderNotification::class, 'onStatusChanged']);

        /*
         * Availability cache invalidation (audit C-2).
         *
         * Registered on the MODELS rather than at each call site, so every path
         * that changes a booking or a working-hours row invalidates the cache —
         * including paths added later. Both observers implement
         * ShouldHandleEventsAfterCommit, so a rolled-back transaction never
         * evicts a still-accurate entry.
         */
        Booking::observe(BookingAvailabilityObserver::class);
        StaffSchedule::observe(ScheduleAvailabilityObserver::class);
        BranchSchedule::observe(ScheduleAvailabilityObserver::class);
        TimeOff::observe(ScheduleAvailabilityObserver::class);
    }
}

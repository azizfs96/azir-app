import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/data/my_stores_repository.dart';
import '../../stores/data/store_repository.dart';
import '../../stores/domain/storefront.dart';
import '../../stores/presentation/store_avatar.dart';
import '../data/booking_repository.dart';
import '../data/store_bookings_provider.dart';
import '../domain/booking_flow.dart';
import 'steps/date_step.dart';
import 'steps/date_time_step.dart';
import 'steps/notes_step.dart';
import 'steps/payment_step.dart';
import 'steps/picker_step.dart';
import 'steps/service_step.dart';
import 'steps/confirm_step.dart';
import 'steps/staff_step.dart';
import 'steps/time_step.dart';

/// ============================================================================
/// THE BOOKING FLOW (spec §9, §41, §43)
///
/// This screen renders whatever step list the SERVER sent. It contains no
/// merchant-specific logic and no salon-specific assumptions:
///
///     final step = flow.current;
///     return switch (step.type) { ... }
///
/// Merchant A sees service -> staff -> date -> time; Merchant B sees
/// branch -> service -> date -> time. Same code, different data.
/// ============================================================================
class BookingFlowScreen extends ConsumerStatefulWidget {
  const BookingFlowScreen({super.key, required this.token, this.preselectedService});

  final String token;
  final StoreService? preselectedService;

  @override
  ConsumerState<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends ConsumerState<BookingFlowScreen> {
  BookingFlow? _flow;

  @override
  void initState() {
    super.initState();

    /*
     * Refresh the storefront on every entry to the flow.
     *
     * The provider caches per token for the whole session, so without this a
     * price change, a deactivated service or a reconfigured flow never reached
     * a customer who had the store open since launch. Post-frame because a
     * provider must not be mutated while the tree is building; the cached
     * value renders instantly and is silently replaced when the fresh one
     * arrives (when() keeps showing data during a refresh).
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(storefrontProvider(widget.token));
    });
  }
  bool _submitting = false;
  String? _error;

  /// Whether the banner should offer Retry. A lost slot is not retryable —
  /// the customer is sent back to pick another time instead.
  bool _errorRetryable = false;

  /// Has the CUSTOMER answered anything in this visit?
  ///
  /// Gates the leave-confirmation: an untouched flow pops silently, a
  /// filled-in one asks first. A service preselected by the storefront tile
  /// does not count — the customer typed nothing to get it, and re-tapping
  /// the tile costs them nothing.
  bool _dirty = false;

  void _ensureFlow(Storefront store) {
    /*
     * Keep the in-progress flow across rebuilds — EXCEPT when the refreshed
     * storefront changed the step list itself. Continuing on steps the
     * merchant no longer has would collect answers the server will reject;
     * starting over on the new configuration is the only correct outcome.
     */
    if (_flow != null) {
      final unchanged = _flow!.steps.length == store.flow.length &&
          Iterable<int>.generate(store.flow.length)
              .every((i) => _flow!.steps[i].type == store.flow[i].type);

      if (unchanged) return;

      _flow = null;
    }

    _flow = BookingFlow(steps: store.flow);

    // Arriving from a service tile means that question is already answered —
    // skip past it rather than asking again (spec §41: no unnecessary screens).
    if (widget.preselectedService != null) {
      _flow!.record(FlowStepType.service, widget.preselectedService);

      while (!_flow!.isLast && _flow!.current.type == FlowStepType.service) {
        _flow!.next();
      }
    }
  }

  void _advance() {
    setState(() {
      _dirty = true;
      _error = null;
      _errorRetryable = false;
      if (!_flow!.next()) return;
    });
  }

  /// Are `date` and `time` adjacent in the server's step list?
  ///
  /// When they are, they are drawn as ONE screen — the server still decided
  /// both steps exist and in what order; combining them is purely a
  /// presentation choice (spec §41: no unnecessary screens).
  /// Going back must never land on the standalone `time` step.
  ///
  /// Because date+time are drawn together, the `time` index is a screen the
  /// customer never actually saw — stopping there on the way back would show
  /// a bare slot list with no day strip, and pressing back again would then
  /// show the same times a second time.
  void _stepBack(BookingFlow flow) {
    setState(() {
      _error = null;
      _errorRetryable = false;
      flow.previous();

      if (flow.current.type == FlowStepType.time &&
          flow.index > 0 &&
          flow.steps[flow.index - 1].type == FlowStepType.date) {
        flow.previous();
      }
    });
  }

  /// Progress across the screens the customer actually SEES.
  ///
  /// flow.progress counts steps, but adjacent date+time render as one screen —
  /// so the bar advanced by two on that screen and by one everywhere else,
  /// and never matched what the customer was looking at.
  double _screenProgress(BookingFlow flow) {
    var screens = 0;
    var current = 0;

    for (var i = 0; i < flow.steps.length; i++) {
      // A `time` right after a `date` is drawn inside the date screen.
      final absorbed = flow.steps[i].type == FlowStepType.time &&
          i > 0 &&
          flow.steps[i - 1].type == FlowStepType.date;

      if (absorbed) continue;

      screens++;
      if (i <= flow.index) current = screens;
    }

    return screens == 0 ? 0 : current / screens;
  }

  /// Leave the flow — the ONLY exit for both the arrow and the system back.
  ///
  /// A filled-in flow used to pop silently from the first step, discarding
  /// service, stylist, date and time with nothing but a screen transition to
  /// show for it. Ask first; an untouched flow still leaves immediately.
  Future<void> _leaveFlow() async {
    if (!_dirty) {
      context.pop();
      return;
    }

    final s = Strings.of(context);

    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.discardBookingTitle),
        content: Text(s.discardBookingBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.keepBooking),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.bad),
            child: Text(s.discardBooking),
          ),
        ],
      ),
    );

    // Navigator.pop is deliberate here: canPop is false while dirty, which
    // blocks maybePop but not a direct pop.
    if (leave == true && mounted) context.pop();
  }

  bool _dateAndTimeAreAdjacent(BookingFlow flow) {
    final i = flow.index;

    return flow.current.type == FlowStepType.date &&
        i + 1 < flow.steps.length &&
        flow.steps[i + 1].type == FlowStepType.time;
  }

  Future<void> _submit(Storefront store) async {
    setState(() {
      _submitting = true;
      _error = null;
      _errorRetryable = false;
    });

    final s = Strings.of(context);

    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .create(_flow!.toBookingPayload(store.token));

      ref.invalidate(myStoresProvider);

      /*
       * The storefront's "my bookings" list is cached per token for the whole
       * session, so without this the customer returned from the confirmation
       * screen to a list that did not contain the booking they had just made.
       */
      ref.invalidate(storeBookingsProvider(store.token));

      if (!mounted) return;
      context.pushReplacement('/booking/confirmed', extra: booking);
    } on Object catch (error) {
      final failure = ApiFailure.from(error);

      if (!mounted) return;

      setState(() {
        _submitting = false;
        _errorRetryable = !failure.isSlotTaken;

        /*
         * Only a message the SERVER localized is fit to show. Everything else
         * reaching this point is transport detail or an exception's toString,
         * which used to be rendered verbatim into an Arabic screen.
         *
         * Losing a slot race is not a generic failure — tell the customer what
         * happened and send them back to pick another time (§6.3).
         */
        _error = failure.isSlotTaken
            ? s.slotTaken
            : failure.fromServer
                ? failure.message
                : s.bookingFailed;
      });

      if (failure.isSlotTaken) {
        /*
         * Their chosen time is gone. Send them back to the screen they picked
         * it on — which is the DATE step when the two are combined, so the day
         * strip comes back with it and the slots refetch.
         */
        final timeIndex = _flow!.steps.indexWhere((step) => step.type == FlowStepType.time);

        if (timeIndex >= 0) {
          _flow!.record(FlowStepType.time, null);

          final target = (timeIndex > 0 && _flow!.steps[timeIndex - 1].type == FlowStepType.date)
              ? timeIndex - 1
              : timeIndex;

          setState(() => _flow!.goTo(target));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(widget.token));

    return store.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      // A dead end here meant backing all the way out and re-entering was the
      // only recovery from one failed request. Same pattern as the storefront
      // screen: say what happened, offer Retry.
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.error, style: const TextStyle(color: AppColors.ink500)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(storefrontProvider(widget.token)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
                child: Text(s.retry),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        _ensureFlow(data);
        final flow = _flow!;

        /*
         * THE SYSTEM BACK GESTURE MUST STEP, NOT EXIT.
         *
         * The whole flow is ONE route holding its position in state, so the
         * iOS edge-swipe and the Android hardware button used to pop the route
         * outright and silently discard every answer. Only the AppBar arrow
         * stepped backwards, which meant back did two different things
         * depending on how the customer performed it — and on iPhone the
         * edge-swipe is the one they reach for.
         *
         * canPop is true only on the first step, where leaving the flow IS the
         * correct outcome and matches what the arrow does (context.pop()).
         */
        return PopScope(
          // Free to pop only when nothing would be lost; otherwise the pop is
          // intercepted and either steps back or asks about discarding.
          canPop: flow.isFirst && !_dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;

            if (flow.isFirst) {
              _leaveFlow();
            } else {
              _stepBack(flow);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(data.name),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (flow.isFirst) {
                    _leaveFlow();
                  } else {
                    _stepBack(flow);
                  }
                },
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _screenProgress(flow),
                  minHeight: 2,
                  backgroundColor: AppColors.ink100,
                  color: AppColors.ink900,
                ),
              ),
            ),
            body: Column(
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: AppColors.badSoft,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.bad, fontSize: 14),
                          ),
                        ),
                        // A failure the customer cannot act on is a dead end;
                        // a lost slot is excluded because they are already
                        // being sent back to choose another time.
                        if (_errorRetryable && !_submitting)
                          TextButton(
                            onPressed: () => _submit(data),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.bad,
                              minimumSize: const Size(64, 44),
                            ),
                            child: Text(s.retry),
                          ),
                      ],
                    ),
                  ),
                Expanded(child: _buildStep(data, flow, s)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The whole point of this file.
  ///
  /// One widget per step TYPE — never one screen per merchant. Adding a step
  /// type later means one case here and one widget, and it becomes available to
  /// every merchant whose configuration requests it, with no app release.
  Widget _buildStep(Storefront store, BookingFlow flow, Strings s) {
    final step = flow.current;

    /*
     * Availability cannot be asked for without a service. The current engine
     * always orders `service` before `date`/`time`, but the flow is SERVER
     * data and the app's own rule is to degrade on a payload it does not
     * expect — this used to be `flow.serviceId!`, which turned a malformed
     * step list into a null-check crash instead.
     */
    if (flow.serviceId == null &&
        (step.type == FlowStepType.date || step.type == FlowStepType.time)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            s.error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.ink500),
          ),
        ),
      );
    }

    return switch (step.type) {
      FlowStepType.service => ServiceStep(
        store: store,
        s: s,
        brand: brandColorOf(store.brandColor),
        selected: flow.service,
        onSelected: (service) {
          flow.record(FlowStepType.service, service);
          _advance();
        },
      ),

      FlowStepType.branch => PickerStep<StoreBranch>(
        title: s.chooseBranch,
        items: store.branches,
        selected: flow.branch,
        labelOf: (branch) => branch.name,
        subtitleOf: (branch) => branch.address,
        onSelected: (branch) {
          flow.record(FlowStepType.branch, branch);
          _advance();
        },
      ),

      // Only reachable when the merchant enabled staff selection; otherwise the
      // server omitted this step and assigns someone itself (spec §9).
      FlowStepType.staff => StaffStep(
        staff: store.staff,
        s: s,
        brand: brandColorOf(store.brandColor),
        selected: flow.staff,
        // "Any available" is a first-class choice, not an absence of one —
        // and like any choice, it must LOOK chosen on the way back.
        allowAny: step.allowAny,
        anySelected: flow.choseAnyStaff,
        onAnySelected: () {
          flow.record(FlowStepType.staff, null);
          _advance();
        },
        onSelected: (member) {
          flow.record(FlowStepType.staff, member);
          _advance();
        },
      ),

      // Date + time together when the server put them side by side.
      FlowStepType.date when _dateAndTimeAreAdjacent(flow) => DateTimeStep(
        storeToken: store.token,
        serviceId: flow.serviceId!,
        s: s,
        brand: brandColorOf(store.brandColor),
        selectedDate: flow.date,
        selectedSlot: flow.slotStartsAt,
        maxAdvanceDays: store.maxAdvanceDays,
        leadTimeMinutes: store.minLeadTimeMinutes,
        branchId: flow.branch?.id,
        staffId: flow.staff?.id,
        onPicked: (date, slot) {
          flow.record(FlowStepType.date, date);

          /*
           * The server may name who serves this slot. That is an ASSIGNMENT,
           * not the customer's choice — writing it in as an answer overwrote
           * "any available", so coming back here re-queried availability
           * filtered to that one stylist and hid everyone else's times.
           *
           * Still AFTER record(date), which clears the assignment along with
           * the time it was derived from.
           */
          if (slot.staffId != null && flow.staff == null) {
            flow.assignStaff(
              StoreStaff(id: slot.staffId!, name: slot.staffName ?? ''),
            );
          }

          flow.record(FlowStepType.time, slot.startsAt);

          // Both questions are answered, so step past both.
          setState(() {
            _dirty = true;
            _error = null;
            flow.next();
            flow.next();
          });
        },
      ),

      // An engine that sends a date with no time still gets the plain step.
      FlowStepType.date => DateStep(
        selected: flow.date,
        maxAdvanceDays: store.maxAdvanceDays,
        leadTimeMinutes: store.minLeadTimeMinutes,
        onSelected: (date) {
          flow.record(FlowStepType.date, date);
          _advance();
        },
      ),

      FlowStepType.time => TimeStep(
        storeToken: store.token,
        serviceId: flow.serviceId!,
        date: flow.date ?? DateTime.now(),
        selectedSlot: flow.slotStartsAt,
        branchId: flow.branch?.id,
        staffId: flow.staff?.id,
        onSelected: (slot) {
          /*
           * The stylist the server picked for this slot is an ASSIGNMENT, not
           * an answer. Keeping it out of the answers map is what lets "any
           * available" survive a trip backwards, and it also removes the old
           * ordering trap: assignStaff does not clear the chosen time, so it
           * can no longer wipe the starts_at we are about to record.
           */
          if (slot.staffId != null && flow.staff == null) {
            flow.assignStaff(
              StoreStaff(id: slot.staffId!, name: slot.staffName ?? ''),
            );
          }

          flow.record(FlowStepType.time, slot.startsAt);
          _advance();
        },
      ),

      FlowStepType.notes => NotesStep(
        initial: flow.notes,
        onSubmitted: (text) {
          flow.record(FlowStepType.notes, text);
          _advance();
        },
      ),

      // Online payment is out of scope for the MVP, so the server always sends
      // mode 'pay_at_store'. The step still exists so the customer knows.
      FlowStepType.payment => PaymentStep(mode: step.mode ?? 'pay_at_store', onContinue: _advance),

      FlowStepType.confirm => ConfirmStep(
        store: store,
        flow: flow,
        s: s,
        submitting: _submitting,
        onConfirm: () => _submit(store),
      ),

      // A step this build does not recognise is skipped, not fatal — the server
      // may be newer than the app.
      FlowStepType.unknown => const SizedBox.shrink(),
    };
  }
}

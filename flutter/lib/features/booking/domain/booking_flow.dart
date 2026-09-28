import '../../stores/domain/storefront.dart';

/// ============================================================================
/// THE CONFIGURABLE BOOKING FLOW (spec §9, §31, §43)
///
/// This class is the reason Wasla can onboard a merchant without a release.
///
///   Merchant A (staff selection on):
///     service -> staff -> date -> time -> notes -> payment -> confirm
///   Merchant B (staff selection off, 3 branches):
///     branch -> service -> date -> time -> payment -> confirm
///
/// It holds the server-provided step list and an answers map, and knows NOTHING
/// about salons. Adding a step type later is one enum case plus one widget, and
/// it lights up for every merchant whose configuration asks for it.
/// ============================================================================
class BookingFlow {
  BookingFlow({required this.steps, Map<FlowStepType, Object?>? answers})
      : _answers = {...?answers};

  final List<FlowStep> steps;
  final Map<FlowStepType, Object?> _answers;

  /// The stylist the SERVER attached to the chosen slot.
  ///
  /// Deliberately NOT kept in `_answers`: it is not something the customer
  /// chose. Conflating the two is what broke "any available" — the assignment
  /// was written in as if it were an answer, so navigating back re-queried
  /// availability filtered to that one stylist and silently hid every time the
  /// others could have served.
  ///
  /// The CHOICE (`staff`) drives what availability is requested.
  /// The ASSIGNMENT (this) only ever reaches the booking payload.
  StoreStaff? _assignedStaff;

  int _index = 0;

  int get index => _index;
  FlowStep get current => steps[_index];
  bool get isFirst => _index == 0;
  bool get isLast => _index >= steps.length - 1;

  /// 0.0 .. 1.0 for the progress indicator.
  double get progress => steps.isEmpty ? 0 : (_index + 1) / steps.length;

  Object? answer(FlowStepType type) => _answers[type];

  int? get serviceId => (_answers[FlowStepType.service] as StoreService?)?.id;
  StoreService? get service => _answers[FlowStepType.service] as StoreService?;
  StoreStaff? get staff => _answers[FlowStepType.staff] as StoreStaff?;
  StoreBranch? get branch => _answers[FlowStepType.branch] as StoreBranch?;
  DateTime? get date => _answers[FlowStepType.date] as DateTime?;
  String? get slotStartsAt => _answers[FlowStepType.time] as String?;
  String? get notes => _answers[FlowStepType.notes] as String?;

  /// Who the server said would serve the chosen slot, when the customer did
  /// not name anyone. Never treated as a selection.
  StoreStaff? get assignedStaff => _assignedStaff;

  /// Did the customer explicitly pick "any available"?
  ///
  /// An explicit null answer, distinct from the question not being asked yet —
  /// the same distinction canAdvance already relies on.
  bool get choseAnyStaff =>
      _answers.containsKey(FlowStepType.staff) && _answers[FlowStepType.staff] == null;

  /// Record the stylist the server attached to the picked slot.
  ///
  /// Unlike [record], this does NOT clear the chosen time — the assignment is
  /// derived FROM that time, so invalidating it here would be circular.
  void assignStaff(StoreStaff? member) => _assignedStaff = member;

  void record(FlowStepType type, Object? value) {
    _answers[type] = value;

    /*
     * Changing an earlier answer invalidates the ones that depend on it.
     *
     * Picking a different service after choosing a time must clear that time —
     * a 30-minute slot is not valid for a 120-minute service, and silently
     * carrying it forward would send an unbookable request to the server.
     */
    switch (type) {
      case FlowStepType.service:
      case FlowStepType.branch:
        _answers.remove(FlowStepType.staff);
        _answers.remove(FlowStepType.date);
        _answers.remove(FlowStepType.time);
        // The assignment described a slot that no longer applies.
        _assignedStaff = null;
      case FlowStepType.staff:
      case FlowStepType.date:
        _answers.remove(FlowStepType.time);
        _assignedStaff = null;
      default:
        break;
    }
  }

  /// Can the customer move on from the current step?
  bool get canAdvance {
    final step = current;
    if (!step.required) return true;

    return switch (step.type) {
      FlowStepType.service => _answers[FlowStepType.service] != null,
      // 'Any available staff' is a valid answer, represented by an explicit
      // null entry rather than a missing key.
      FlowStepType.staff => _answers.containsKey(FlowStepType.staff),
      FlowStepType.branch => _answers[FlowStepType.branch] != null,
      FlowStepType.date => _answers[FlowStepType.date] != null,
      FlowStepType.time => _answers[FlowStepType.time] != null,
      FlowStepType.notes => true,
      FlowStepType.payment => true,
      FlowStepType.confirm => true,
      FlowStepType.unknown => true,
    };
  }

  bool next() {
    if (isLast) return false;
    _index++;
    return true;
  }

  bool previous() {
    if (isFirst) return false;
    _index--;
    return true;
  }

  void goTo(int index) {
    if (index >= 0 && index < steps.length) _index = index;
  }

  /// The POST /bookings payload.
  ///
  /// Only sends what the merchant's flow actually collected — a staff_id is
  /// never invented for a merchant who hides staff (the server ignores it
  /// anyway, but sending it would be lying about what the customer chose).
  Map<String, dynamic> toBookingPayload(String storeToken) {
    // The customer's own choice wins; the server's assignment is the fallback
    // for "any available". When the merchant hides staff the server strips
    // staff from its slots, so both are null and no staff_id is invented.
    final servedBy = staff ?? _assignedStaff;

    return {
      'store_token': storeToken,
      'service_id': serviceId,
      'starts_at': slotStartsAt,
      if (branch != null) 'branch_id': branch!.id,
      if (servedBy != null) 'staff_id': servedBy.id,
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    };
  }
}

import 'package:flutter/material.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../stores/domain/storefront.dart';

/// ============================================================================
/// CHOOSE A STAFF MEMBER (spec §9, §15)
///
///   اختر الموظف
///
///   ┌──────────────────────────────────┐
///   │ ⚡  أي موظف متاح          مُوصى به │  ← a real choice, listed first
///   │     أقرب موعد متاح                │
///   └──────────────────────────────────┘
///
///   ┌─────────┐  ┌─────────┐
///   │   (س)   │  │   (ر)   │              ← a person, not a table row
///   │  سارة   │  │  ريم    │
///   │ مصففة   │  │ مصففة   │
///   └─────────┘  └─────────┘
///
/// Only reachable when the merchant enabled staff_selection; otherwise the
/// server omits this step entirely and assigns someone itself.
///
/// "Any available" is listed FIRST and recommended, because it genuinely gets
/// the customer an earlier appointment — the engine can offer every stylist's
/// free slots instead of one person's.
/// ============================================================================
class StaffStep extends StatelessWidget {
  const StaffStep({
    super.key,
    required this.staff,
    required this.s,
    required this.brand,
    required this.selected,
    required this.allowAny,
    required this.onSelected,
    required this.onAnySelected,
    this.anySelected = false,
  });

  final List<StoreStaff> staff;
  final Strings s;
  final Color brand;
  final StoreStaff? selected;
  final bool allowAny;

  /// The customer's current answer IS "any available" — show it as chosen,
  /// exactly as a named stylist's card would be.
  final bool anySelected;
  final ValueChanged<StoreStaff> onSelected;
  final VoidCallback onAnySelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          s.chooseStaff,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.chooseStaffHint,
          style: const TextStyle(fontSize: 14, color: AppColors.ink500),
        ),
        const SizedBox(height: 18),

        if (allowAny) ...[
          _AnyStaffCard(s: s, brand: brand, selected: anySelected, onTap: onAnySelected),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.ink200)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  s.orChooseSpecific,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink400),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.ink200)),
            ],
          ),
          const SizedBox(height: 18),
        ],

        // A grid, because a stylist is a person: the avatar carries more
        // recognition than a name in a list row, and it is how customers
        // actually remember "the one who did my colour last time".
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: staff.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, i) => _StaffCard(
            member: staff[i],
            brand: brand,
            selected: staff[i].id == selected?.id,
            onTap: () => onSelected(staff[i]),
          ),
        ),
      ],
    );
  }
}

/// "Any available" — presented as the fastest route, not as a fallback.
class _AnyStaffCard extends StatelessWidget {
  const _AnyStaffCard({
    required this.s,
    required this.brand,
    required this.onTap,
    this.selected = false,
  });

  final Strings s;
  final Color brand;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? brand : brand.withValues(alpha: 0.35),
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
            color: brand.withValues(alpha: selected ? 0.08 : 0.04),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.bolt_rounded, size: 22, color: brand),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.anyStaff,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: brand,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.recommended,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.anyStaffHint,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.ink500),
                    ),
                  ],
                ),
              ),
              selected
                  // The same check the staff cards use, so "chosen" reads the
                  // same everywhere on this screen.
                  ? Container(
                      decoration: BoxDecoration(color: brand, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(3),
                      child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                    )
                  : const Icon(Icons.chevron_right_rounded,
                      size: 22, color: AppColors.ink300),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.member,
    required this.brand,
    required this.selected,
    required this.onTap,
  });

  final StoreStaff member;
  final Color brand;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = member.name.trim().isEmpty
        ? '؟'
        : String.fromCharCodes(member.name.trim().runes.take(1));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? brand.withValues(alpha: 0.05) : Colors.white,
            border: Border.all(
              color: selected ? brand : AppColors.ink200,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: brand.withValues(alpha: selected ? 0.18 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: brand,
                      ),
                    ),
                  ),
                  if (selected)
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: brand,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.check_rounded,
                            size: 11, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink900,
                ),
              ),
              if (member.title != null && member.title!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  member.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

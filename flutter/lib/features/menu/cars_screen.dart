import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import 'car_repository.dart';

const _brands = [
  'تويوتا', 'نيسان', 'لكزس', 'شيفروليه', 'جي إم سي', 'ميتسوبيشي', 'مرسيدس',
  'هيونداي', 'كيا', 'فورد', 'هوندا', 'مازدا', 'جيب', 'بي إم دبليو',
];

const _colors = <(String, Color)>[
  ('أبيض', Color(0xFFF2F2F2)), ('أسود', Color(0xFF111111)), ('فضي', Color(0xFFC4C4CC)),
  ('رمادي', Color(0xFF6B6B76)), ('أحمر', Color(0xFFC0392B)), ('أزرق', Color(0xFF2453B8)),
  ('أخضر', Color(0xFF1E7A46)), ('ذهبي', Color(0xFFD4A017)), ('بني', Color(0xFF6B4423)),
  ('برتقالي', Color(0xFFE1701A)),
];

/// Saved cars for curbside pickup (Jahez's "my cars" 10–14, in one form).
class CarsScreen extends ConsumerWidget {
  const CarsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final cars = ref.watch(carsProvider);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.myCars),
      ),
      body: cars.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => Center(child: Text(s.error, style: const TextStyle(color: AppColors.ink500))),
        data: (list) => list.isEmpty
            ? _empty(s)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _CarCard(
                  car: list[i],
                  s: s,
                  onDelete: () async {
                    await ref.read(carRepositoryProvider).remove(list[i].id);
                    ref.invalidate(carsProvider);
                  },
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: FilledButton.icon(
          onPressed: () => _addSheet(context, ref, s),
          icon: const Icon(Icons.add_rounded),
          label: Text(s.addCar, style: const TextStyle(fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink900,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      ),
    );
  }

  Widget _empty(Strings s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.directions_car_outlined, size: 46, color: AppColors.ink300),
              const SizedBox(height: 14),
              Text(s.noCars,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink900)),
              const SizedBox(height: 6),
              Text(s.noCarsHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink500)),
            ],
          ),
        ),
      );

  Future<void> _addSheet(BuildContext context, WidgetRef ref, Strings s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _AddCarSheet(
          s: s,
          onSave: (brand, color, letters, numbers) async {
            await ref.read(carRepositoryProvider).add(
                brand: brand, color: color, plateLetters: letters, plateNumbers: numbers);
            ref.invalidate(carsProvider);
          },
        ),
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car, required this.s, required this.onDelete});
  final CustomerCar car;
  final Strings s;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.directions_car_rounded, color: AppColors.ink900),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${car.brand} ${car.color}',
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                const SizedBox(height: 3),
                Text('${car.plateLetters} ${car.plateNumbers}',
                    style: const TextStyle(fontSize: 13, color: AppColors.ink500)),
              ],
            ),
          ),
          if (car.isDefault)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.ink100, borderRadius: BorderRadius.circular(20)),
              child: Text(s.defaultLabel,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink500)),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.ink400),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _AddCarSheet extends StatefulWidget {
  const _AddCarSheet({required this.s, required this.onSave});
  final Strings s;
  final Future<void> Function(String brand, String color, String letters, String numbers) onSave;

  @override
  State<_AddCarSheet> createState() => _AddCarSheetState();
}

class _AddCarSheetState extends State<_AddCarSheet> {
  String? _brand;
  String? _color;
  final _letters = TextEditingController();
  final _numbers = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _letters.dispose();
    _numbers.dispose();
    super.dispose();
  }

  bool get _valid =>
      _brand != null && _color != null && _letters.text.trim().isNotEmpty && _numbers.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.ink200, borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                _label(s.chooseBrand),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final b in _brands)
                      _Chip(label: b, selected: _brand == b, onTap: () => setState(() => _brand = b)),
                  ],
                ),
                const SizedBox(height: 22),
                _label(s.carColorLabel),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final c in _colors)
                      _ColorChip(name: c.$1, color: c.$2, selected: _color == c.$1,
                          onTap: () => setState(() => _color = c.$1)),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(s.plateLettersLabel),
                          TextField(
                            controller: _letters,
                            textAlign: TextAlign.center,
                            onChanged: (_) => setState(() {}),
                            decoration: _fieldDeco('أ ب ج'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(s.plateNumbersLabel),
                          TextField(
                            controller: _numbers,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: _fieldDeco('4592'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: !_valid || _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        await widget.onSave(
                            _brand!, _color!, _letters.text.trim(), _numbers.text.trim());
                        if (context.mounted) Navigator.of(context).pop();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink900,
                  disabledBackgroundColor: AppColors.ink200,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: Text(s.saveCar, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink900)),
      );

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.cream,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink900 : AppColors.ink100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.ink700)),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.name, required this.color, required this.selected, required this.onTap});
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink900 : AppColors.ink100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                border: Border.all(color: AppColors.ink300, width: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            Text(name,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.ink700)),
          ],
        ),
      ),
    );
  }
}

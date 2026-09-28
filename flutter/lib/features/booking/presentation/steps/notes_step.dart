import 'package:flutter/material.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';

/// Optional customer notes — only shown when the merchant enabled them (§10).
class NotesStep extends StatefulWidget {
  const NotesStep({super.key, required this.onSubmitted, this.initial});

  final String? initial;
  final void Function(String?) onSubmitted;

  @override
  State<NotesStep> createState() => _NotesStepState();
}

class _NotesStepState extends State<NotesStep> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                s.addNotes,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(
              onPressed: () => widget.onSubmitted(_controller.text),
              child: Text(s.next),
            ),
          ),
        ),
      ],
    );
  }
}

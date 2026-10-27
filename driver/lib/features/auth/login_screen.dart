import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

/// Folds Arabic-Indic / Persian digits to ASCII (what an Arabic keyboard types).
String _asciiDigits(String s) {
  const from = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  final out = StringBuffer();
  for (final r in s.runes) {
    final i = from.runes.toList().indexOf(r);
    out.writeCharCode(i < 0 ? r : 0x30 + (i % 10));
  }
  return out.toString();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = Strings.of(context);
    final phone = _asciiDigits(_phone.text.trim());
    final password = _password.text;
    if (phone.isEmpty || password.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(sessionProvider.notifier).login(phone, password);
      AppHaptics.success();
    } catch (e) {
      final f = ApiFailure.from(e);
      if (!mounted) return;
      setState(() {
        _error = switch (f.code) {
          'INVALID_CREDENTIALS' || 'VALIDATION_FAILED' => s.signInFailed,
          'ACCOUNT_DISABLED' => s.accountDisabled,
          _ => f.fromServer ? f.message : (f.statusCode == null ? s.offlineError : s.genericError),
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 38),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(s.appName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(s.tagline, style: const TextStyle(color: AppColors.ink2, fontSize: 15)),
                  const SizedBox(height: 32),
                  Text(s.signInTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(s.signInHint, style: const TextStyle(color: AppColors.ink2, height: 1.5)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    // Western digits even on an Arabic keyboard: a phone number
                    // reads the same everywhere, and the API expects ASCII.
                    style: const TextStyle(locale: Locale('en'), fontSize: 16, fontWeight: FontWeight.w600),
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: InputDecoration(
                      hintText: '05XXXXXXXX',
                      labelText: s.phone,
                      prefixIcon: const Icon(Icons.phone_iphone_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: s.password,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: AppMotion.dur(context, AppMotion.base),
                    curve: AppMotion.curve,
                    alignment: Alignment.topCenter,
                    child: _error == null
                        ? const SizedBox(height: 20)
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.badSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: AppColors.bad, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: AppColors.bad,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  PrimaryButton(label: s.signIn, onPressed: _submit, loading: _busy),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

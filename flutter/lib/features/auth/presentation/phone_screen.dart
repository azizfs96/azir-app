import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_repository.dart';

/// Customer sign-in: phone + OTP (spec §34). No password anywhere.
///
/// Deliberately reached AFTER the customer has picked a time — they see value
/// before being asked for anything (spec §41).
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key, this.redirectTo});

  final String? redirectTo;

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _devMode = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() { _busy = true; _error = null; });
    try {
      final dev = await ref.read(authRepositoryProvider).requestCode(_phone.text);
      setState(() { _codeSent = true; _devMode = dev; });
    } on Object catch (error) {
      setState(() => _error = ApiFailure.from(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepositoryProvider).verify(
            phone: _phone.text,
            code: _code.text,
          );
      ref.invalidate(isSignedInProvider);

      // Now that there's an account, register this device for order-update push.
      unawaited(ref.read(pushServiceProvider).registerIfSignedIn());

      if (!mounted) return;
      context.go(widget.redirectTo ?? '/');
    } on Object catch (error) {
      setState(() => _error = ApiFailure.from(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _codeSent ? s.verifyCode : s.phoneNumber,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                ),
              ),
              const SizedBox(height: 8),
              if (_codeSent)
                Text(
                  s.codeSentTo(_phone.text),
                  style: const TextStyle(fontSize: 14, color: AppColors.ink500),
                ),
              const SizedBox(height: 24),

              if (!_codeSent)
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  // Saudi numbers are Latin digits even in Arabic UI.
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(hintText: '05xxxxxxxx'),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                )
              else
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 24, letterSpacing: 12),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),

              // Only shown while the API runs with the fixed development code,
              // so testers are not left guessing. Never true in production.
              if (_codeSent && _devMode) ...[
                const SizedBox(height: 4),
                Text(
                  s.devCodeHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.warn),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.bad, fontSize: 14)),
              ],

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_codeSent ? s.verify : s.sendCode),
              ),

              if (_codeSent)
                TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: Text(s.resend),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

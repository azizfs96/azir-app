import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/localization/strings.dart';
import '../domain/store_token_parser.dart';

/// ============================================================================
/// THE QR SCANNER (spec §6)
///
///   Scan QR -> resolve merchant/store -> open merchant inside Wasla
///
/// The scanned payload is a Wasla deep link (wasla.sa/s/8F72K); the token is
/// extracted and handed to the storefront route, which resolves it and adds it
/// to My Stores.
/// ============================================================================
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);

  /// Guards against the detector firing several times for one physical code.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final token = StoreTokenParser.parse(barcode.rawValue);
      if (token == null) continue;

      _handled = true;
      context.pushReplacement('/s/$token');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(s.scanTitle, style: const TextStyle(color: Colors.white)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Viewfinder.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              children: [
                Text(
                  s.scanHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                // The manual fallback: for a damaged code, and for deferred
                // deep links that failed to match on iOS (§8.3).
                TextButton(
                  onPressed: () => _promptForCode(context, s),
                  child: Text(s.enterCode, style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptForCode(BuildContext context, Strings s) async {
    final controller = TextEditingController();

    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.enterCode),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: s.storeCode),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            child: Text(s.confirm),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    final cleaned = StoreTokenParser.parse(token);
    if (cleaned != null) context.pushReplacement('/s/$cleaned');
  }
}

/// Extracting a store token from a scanned code (spec §6, §24).
///
/// Pure and dependency-free so it can be tested without a camera, a widget
/// tree, or a running app — this is the one piece of scanner logic that can
/// actually be wrong.
abstract final class StoreTokenParser {
  /// Characters a token can contain (ARCHITECTURE.md §8.2): Crockford-style
  /// base32 with 0 1 I L O U removed, because these codes get printed on a
  /// salon window and read aloud over the phone.
  static const alphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Must match TokenGenerator::STORE_TOKEN_LENGTH on the server.
  static const tokenLength = 8;

  /// The path segment in wasla.sa/s/8F72K
  static const linkSegment = 's';

  static final _invalid = RegExp('[^$alphabet]');
  static final _separators = RegExp(r'[\s\-_]');

  /// Accepts a Wasla deep link or a bare token; returns null for anything else.
  ///
  /// REJECTS rather than salvages. An earlier version stripped every character
  /// outside the alphabet, which meant scanning ANY qr code — a wifi config, a
  /// competitor's URL — produced a plausible-looking token and sent the
  /// customer to a "store not found" screen. `https://example.com` became
  /// `HTTPSEXAMPECM`. A code that is not ours must fail as not ours.
  static String? parse(String? raw) {
    if (raw == null) return null;

    var value = raw.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);

    if (uri != null && uri.hasScheme) {
      // A URL is only accepted when it has the Wasla store-link shape.
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final index = segments.indexOf(linkSegment);

      if (index < 0 || index + 1 >= segments.length) return null;

      value = segments[index + 1];
    }

    value = value.split('?').first.split('#').first;

    // People type what they see, so fold the lookalikes the alphabet excludes —
    // the same mapping the server's TokenGenerator::normalize applies.
    final folded = value
        .toUpperCase()
        .replaceAll(_separators, '')
        .replaceAll('0', 'D')
        .replaceAll('O', 'D')
        .replaceAll('1', 'J')
        .replaceAll('I', 'J')
        .replaceAll('L', 'J')
        .replaceAll('U', 'V');

    // Anything still outside the alphabet means this was never a token.
    if (folded.isEmpty || _invalid.hasMatch(folded)) return null;

    return folded.length == tokenLength ? folded : null;
  }
}

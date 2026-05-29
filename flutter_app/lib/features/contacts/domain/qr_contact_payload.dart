import 'dart:convert';

/// App-specific payload encoded inside a Lumio "add me" QR code.
///
/// The QR is intentionally namespaced (`app: lumio`, `t: contact`) so that
/// scanning an arbitrary/foreign QR is rejected as invalid rather than being
/// mistaken for a contact. The friend is added by [email] — that's the field
/// the existing `POST /api/contacts/` endpoint keys on — while [userId] and
/// [name] let the scanner recognise self-scans and show who's being added.
class QrContactPayload {
  final String userId;
  final String email;
  final String name;

  const QrContactPayload({
    required this.userId,
    required this.email,
    required this.name,
  });

  static const _app = 'lumio';
  static const _type = 'contact';
  static const _version = 1;

  /// Compact JSON string embedded in the QR image.
  String encode() => jsonEncode({
        'app': _app,
        'v': _version,
        't': _type,
        'id': userId,
        'email': email,
        'name': name,
      });

  /// Parse a scanned QR's raw text. Returns null for anything that isn't a
  /// well-formed Lumio contact payload (foreign QR, garbage, wrong type).
  static QrContactPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['app'] != _app || decoded['t'] != _type) return null;

      final email = (decoded['email'] as String?)?.trim();
      final id = (decoded['id'] as String?)?.trim();
      if (email == null || email.isEmpty || id == null || id.isEmpty) {
        return null;
      }
      return QrContactPayload(
        userId: id,
        email: email,
        name: (decoded['name'] as String?)?.trim().isNotEmpty == true
            ? (decoded['name'] as String).trim()
            : 'Lumio user',
      );
    } catch (_) {
      return null;
    }
  }
}

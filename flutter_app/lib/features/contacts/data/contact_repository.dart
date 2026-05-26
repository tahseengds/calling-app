import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/models/user.dart';

class ContactRepository {
  final Dio _dio;
  ContactRepository(Dio dio) : _dio = dio;

  Future<List<User>> getContacts() async {
    // Trailing slash is intentional — the backend route is mounted at
    // /api/contacts/, and hitting /api/contacts triggers a 307 redirect
    // which strips the Authorization header (Dio default).
    final resp = await _dio.get<List<dynamic>>('/api/contacts/');
    // Backend returns ContactResponse objects; the actual user data lives in
    // the nested 'contact_user' field.
    return (resp.data ?? [])
        .map((e) => User.fromJson(
              (e as Map<String, dynamic>)['contact_user'] as Map<String, dynamic>,
            ))
        .toList();
  }

  /// Same as [getContacts] but preserves the contact-row id alongside the
  /// nested user — needed for DELETE /api/contacts/{contact_id}, since the
  /// backend keys removal by the row id, not the target user's id.
  Future<List<ContactEntry>> getContactEntries() async {
    final resp = await _dio.get<List<dynamic>>('/api/contacts/');
    return (resp.data ?? [])
        .map((e) => ContactEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Look up the target user by [email]. [nickname] is an optional
  /// display name local to the caller's contact list.
  Future<User> addContact({
    required String email,
    String? nickname,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/contacts/',
      data: {
        'email': email,
        'nickname': ?nickname,
      },
    );
    // Backend returns ContactResponse; user data is in 'contact_user'.
    return User.fromJson(resp.data!['contact_user'] as Map<String, dynamic>);
  }

  /// Remove a contact by its **contact row id** (NOT the target user's id).
  /// The contact id is the `id` field of the ContactResponse returned by
  /// `getContacts()` / `addContact()`.
  Future<void> removeContact(String contactId) =>
      _dio.delete('/api/contacts/$contactId');

  // ── Blocking ──────────────────────────────────────────────────────────
  //
  // The backend treats blocking as a per-contact-row flag, so these
  // helpers preserve the full ContactResponse shape (contact row id +
  // nested user + is_blocked flag) instead of collapsing to User.

  Future<List<BlockedContactEntry>> getBlocked() async {
    final resp = await _dio.get<List<dynamic>>('/api/contacts/');
    return (resp.data ?? [])
        .map((e) => BlockedContactEntry.fromJson(e as Map<String, dynamic>))
        .where((entry) => entry.isBlocked)
        .toList();
  }

  Future<BlockedContactEntry> setBlocked({
    required String contactId,
    required bool blocked,
  }) async {
    final resp = await _dio.put<Map<String, dynamic>>(
      '/api/contacts/$contactId/block',
      data: {'blocked': blocked},
    );
    return BlockedContactEntry.fromJson(resp.data!);
  }
}

/// One contact row, carrying the contact-row id alongside the nested user.
class ContactEntry {
  final String contactId;
  final User user;
  final bool isBlocked;

  const ContactEntry({
    required this.contactId,
    required this.user,
    required this.isBlocked,
  });

  factory ContactEntry.fromJson(Map<String, dynamic> json) => ContactEntry(
        contactId: json['id'] as String,
        user: User.fromJson(json['contact_user'] as Map<String, dynamic>),
        isBlocked: json['is_blocked'] as bool? ?? false,
      );
}

/// One blocked contact row — same shape as [ContactEntry] but historically
/// kept separate so the blocked-contacts screen has a dedicated type.
class BlockedContactEntry {
  final String contactId;
  final User user;
  final bool isBlocked;

  const BlockedContactEntry({
    required this.contactId,
    required this.user,
    required this.isBlocked,
  });

  factory BlockedContactEntry.fromJson(Map<String, dynamic> json) =>
      BlockedContactEntry(
        contactId: json['id'] as String,
        user: User.fromJson(json['contact_user'] as Map<String, dynamic>),
        isBlocked: json['is_blocked'] as bool? ?? false,
      );
}

final contactRepositoryProvider = Provider<ContactRepository>(
  (ref) => ContactRepository(ref.watch(dioProvider)),
);

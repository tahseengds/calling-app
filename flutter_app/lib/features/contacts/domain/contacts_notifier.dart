import 'package:dio/dio.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/user.dart';
import '../data/contact_repository.dart';

/// Thrown when adding a contact that is already in the list.
class DuplicateContactException implements Exception {
  const DuplicateContactException();
}

class ContactsState {
  final List<User> contacts;
  final bool isLoading;
  final String? error;

  const ContactsState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
  });

  ContactsState copyWith({
    List<User>? contacts,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      ContactsState(
        contacts: contacts ?? this.contacts,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class ContactsNotifier extends StateNotifier<ContactsState> {
  final ContactRepository _repo;

  /// Backend identifies contact rows by `contact_id` (not by the target
  /// user's id). The UI works in terms of users, so we keep a side map
  /// `user.id → contact_id` to resolve the right id at delete time.
  final Map<String, String> _contactIdByUserId = {};

  ContactsNotifier(this._repo) : super(const ContactsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entries = await _repo.getContactEntries();
      // Keep the id map for ALL rows (blocked included) so we can still
      // resolve a contact row when unblocking/removing, but only surface
      // non-blocked contacts in the family list — blocked ones live in the
      // dedicated Blocked-contacts screen.
      _contactIdByUserId
        ..clear()
        ..addEntries(entries.map((e) => MapEntry(e.user.id, e.contactId)));
      state = ContactsState(
        contacts: entries
            .where((e) => !e.isBlocked)
            .map((e) => e.user)
            .toList(),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Adds a contact by [email].
  Future<void> addContact({
    required String email,
    String? nickname,
  }) async {
    final user = await _repo.addContact(email: email, nickname: nickname);
    // Optimistically prepend; reload to get server-sorted list and contactId.
    state = state.copyWith(contacts: [user, ...state.contacts]);
    load();
  }

  /// Removes the contact whose target user has [userId]. Looks up the
  /// contact row id from the side map populated by `load()`.
  Future<void> removeContact(String userId) async {
    final contactId = await _resolveContactId(userId);
    if (contactId == null) {
      // We still don't know the row id even after a refresh — surface it so
      // callers can show an error instead of a false "removed" confirmation.
      throw StateError('No contact row for user $userId');
    }

    // Optimistic removal.
    final previous = state.contacts;
    state = state.copyWith(
      contacts: previous.where((c) => c.id != userId).toList(),
    );
    _contactIdByUserId.remove(userId);
    try {
      await _repo.removeContact(contactId);
    } on DioException {
      // Rollback on error and rethrow so callers can surface it.
      load();
      rethrow;
    }
  }

  /// Blocks the contact whose target user has [userId]. Resolves the contact
  /// row id from the side map and flips `is_blocked` on the backend, which
  /// also publishes a `user:blocked` event (ending any in-progress call) and
  /// makes message/call attempts between the two fail server-side.
  ///
  /// The blocked user is removed from the family list immediately; they remain
  /// reachable for un-blocking via the Blocked-contacts screen.
  Future<void> blockContact(String userId) async {
    final contactId = await _resolveContactId(userId);
    if (contactId == null) {
      throw StateError('No contact row for user $userId');
    }

    // Optimistic removal from the visible family list.
    final previous = state.contacts;
    state = state.copyWith(
      contacts: previous.where((c) => c.id != userId).toList(),
    );
    try {
      await _repo.setBlocked(contactId: contactId, blocked: true);
    } on DioException {
      // Rollback to the pre-block list and rethrow so callers can surface it.
      load();
      rethrow;
    }
  }

  /// Resolves the contact-row id for [userId], refreshing from the server once
  /// if it isn't cached yet (e.g. a cold-start deep-link straight into a chat,
  /// before the contacts list has been loaded).
  Future<String?> _resolveContactId(String userId) async {
    final cached = _contactIdByUserId[userId];
    if (cached != null) return cached;
    await load();
    return _contactIdByUserId[userId];
  }

  /// Updates presence for a contact — called by the signaling layer.
  void updatePresence(String userId, PresenceStatus status) {
    state = state.copyWith(
      contacts: state.contacts
          .map((c) => c.id == userId ? c.copyWith(presence: status) : c)
          .toList(),
    );
  }
}

final contactsNotifierProvider =
    StateNotifierProvider<ContactsNotifier, ContactsState>((ref) {
  return ContactsNotifier(ref.watch(contactRepositoryProvider));
});

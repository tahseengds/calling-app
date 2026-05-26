import 'package:dio/dio.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../core/config/app_config.dart';
import '../../../core/mock/mock_data.dart';
import '../../../shared/models/user.dart';
import '../data/contact_repository.dart';

/// Thrown when adding a contact that is already in the list (UI-only mode).
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
    if (AppConfig.uiOnly) {
      state = ContactsState(contacts: List.of(MockData.sampleContacts));
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final entries = await _repo.getContactEntries();
      _contactIdByUserId
        ..clear()
        ..addEntries(entries.map((e) => MapEntry(e.user.id, e.contactId)));
      state = ContactsState(contacts: entries.map((e) => e.user).toList());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Adds a contact by [email].
  Future<void> addContact({
    required String email,
    String? nickname,
  }) async {
    if (AppConfig.uiOnly) {
      final duplicate = state.contacts.any((c) => c.email == email);
      if (duplicate) {
        throw const DuplicateContactException();
      }
      final user = User(
        id: 'mock-${email.hashCode}',
        name: nickname?.isNotEmpty == true ? nickname! : 'Family member',
        email: email,
        lastSeen: DateTime.now(),
      );
      state = state.copyWith(contacts: [user, ...state.contacts]);
      return;
    }
    final user = await _repo.addContact(email: email, nickname: nickname);
    // Optimistically prepend; reload to get server-sorted list and contactId.
    state = state.copyWith(contacts: [user, ...state.contacts]);
    load();
  }

  /// Removes the contact whose target user has [userId]. Looks up the
  /// contact row id from the side map populated by `load()`.
  Future<void> removeContact(String userId) async {
    if (AppConfig.uiOnly) {
      _contactIdByUserId.remove(userId);
      state = state.copyWith(
        contacts: state.contacts.where((c) => c.id != userId).toList(),
      );
      return;
    }
    final contactId = _contactIdByUserId[userId];
    if (contactId == null) {
      // We don't know the row id (e.g. optimistic add hasn't reloaded yet).
      // Refresh and let the user retry — silently ignore for now.
      await load();
      return;
    }

    // Optimistic removal.
    final previous = state.contacts;
    state = state.copyWith(
      contacts: previous.where((c) => c.id != userId).toList(),
    );
    _contactIdByUserId.remove(userId);
    try {
      await _repo.removeContact(contactId);
    } on DioException catch (_) {
      // Rollback on error.
      load();
    }
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

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
      final contacts = await _repo.getContacts();
      state = ContactsState(contacts: contacts);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Throws on failure (notFound, duplicate) so AddContactScreen can show
  /// inline error messages without changing global contacts state.
  ///
  /// Pass either [email] (preferred, matches the email/Google auth flow) or
  /// [phone] (legacy accounts). Exactly one must be non-null.
  Future<void> addContact({
    String? email,
    String? phone,
    String? nickname,
  }) async {
    assert(
      (email == null) ^ (phone == null),
      'addContact requires exactly one of email or phone',
    );
    if (AppConfig.uiOnly) {
      final key = email ?? phone!;
      final duplicate = state.contacts.any(
        (c) => (email != null && c.email == email) ||
            (phone != null && c.phone == phone),
      );
      if (duplicate) {
        throw const DuplicateContactException();
      }
      final user = User(
        id: 'mock-${key.hashCode}',
        name: nickname?.isNotEmpty == true ? nickname! : 'Family member',
        email: email,
        phone: phone,
        lastSeen: DateTime.now(),
      );
      state = state.copyWith(contacts: [user, ...state.contacts]);
      return;
    }
    final user = await _repo.addContact(
      email: email,
      phone: phone,
      nickname: nickname,
    );
    // Optimistically prepend; reload to get server-sorted list.
    state = state.copyWith(contacts: [user, ...state.contacts]);
    load();
  }

  Future<void> removeContact(String userId) async {
    if (AppConfig.uiOnly) {
      state = state.copyWith(
        contacts: state.contacts.where((c) => c.id != userId).toList(),
      );
      return;
    }
    // Optimistic removal.
    state = state.copyWith(
      contacts: state.contacts.where((c) => c.id != userId).toList(),
    );
    try {
      await _repo.removeContact(userId);
    } catch (_) {
      // Rollback on error.
      load();
    }
  }

  /// Updates presence for a contact — called by the signaling layer (prompt 14).
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

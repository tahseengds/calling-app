import '../../shared/models/user.dart';

/// Sample data for [AppConfig.uiOnly] — no backend required.
abstract final class MockData {
  static final User currentUser = User(
    id: 'mock-me',
    name: 'Rose Martinez',
    email: 'rose@example.com',
    lastSeen: DateTime.now(),
    presence: PresenceStatus.online,
  );

  static final List<User> sampleContacts = [
    User(
      id: 'mock-1',
      name: 'Mom',
      email: 'mom@example.com',
      lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
      presence: PresenceStatus.online,
    ),
    User(
      id: 'mock-2',
      name: 'Dad',
      email: 'dad@example.com',
      lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
      presence: PresenceStatus.away,
    ),
    User(
      id: 'mock-3',
      name: 'Sarah',
      email: 'sarah@example.com',
      lastSeen: DateTime.now().subtract(const Duration(days: 1)),
      presence: PresenceStatus.offline,
    ),
    User(
      id: 'mock-4',
      name: 'Grandma Rose',
      email: 'grandma@example.com',
      lastSeen: DateTime.now().subtract(const Duration(minutes: 30)),
      presence: PresenceStatus.online,
    ),
  ];
}

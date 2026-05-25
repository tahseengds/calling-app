import '../../shared/models/user.dart';

/// Sample data for [AppConfig.uiOnly] — no backend required.
abstract final class MockData {
  static final User currentUser = User(
    id: 'mock-me',
    name: 'Rose Martinez',
    phone: '+14155550142',
    lastSeen: DateTime.now(),
    presence: PresenceStatus.online,
  );

  static final List<User> sampleContacts = [
    User(
      id: 'mock-1',
      name: 'Mom',
      phone: '+15559876543',
      lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
      presence: PresenceStatus.online,
    ),
    User(
      id: 'mock-2',
      name: 'Dad',
      phone: '+15557654321',
      lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
      presence: PresenceStatus.away,
    ),
    User(
      id: 'mock-3',
      name: 'Sarah',
      phone: '+15551112222',
      lastSeen: DateTime.now().subtract(const Duration(days: 1)),
      presence: PresenceStatus.offline,
    ),
    User(
      id: 'mock-4',
      name: 'Grandma Rose',
      phone: '+15553334444',
      lastSeen: DateTime.now().subtract(const Duration(minutes: 30)),
      presence: PresenceStatus.online,
    ),
  ];
}

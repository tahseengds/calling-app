enum PresenceStatus { online, offline, away }

class User {
  final String id;
  final String name;
  final String phone;
  final String? avatarUrl;
  final DateTime lastSeen;
  final PresenceStatus presence;

  const User({
    required this.id,
    required this.name,
    required this.phone,
    this.avatarUrl,
    required this.lastSeen,
    this.presence = PresenceStatus.offline,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        avatarUrl: json['avatar_url'] as String?,
        lastSeen: DateTime.parse(json['last_seen'] as String),
        presence: PresenceStatus.values.firstWhere(
          (e) => e.name == (json['presence'] as String? ?? 'offline'),
          orElse: () => PresenceStatus.offline,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'avatar_url': avatarUrl,
        'last_seen': lastSeen.toUtc().toIso8601String(),
        'presence': presence.name,
      };

  User copyWith({PresenceStatus? presence}) => User(
        id: id,
        name: name,
        phone: phone,
        avatarUrl: avatarUrl,
        lastSeen: lastSeen,
        presence: presence ?? this.presence,
      );
}

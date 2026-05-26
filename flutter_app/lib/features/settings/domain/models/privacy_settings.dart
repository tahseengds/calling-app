// Mirror of backend/api/app/schemas/settings.py:PrivacySettings.

enum VisibilityLevel { everyone, contacts, nobody }

enum OnlineVisibility { everyone, sameAsLastSeen }

enum GroupsWhoCanAdd { everyone, contacts }

extension VisibilityLevelX on VisibilityLevel {
  String get wire => switch (this) {
        VisibilityLevel.everyone => 'everyone',
        VisibilityLevel.contacts => 'contacts',
        VisibilityLevel.nobody => 'nobody',
      };

  String get label => switch (this) {
        VisibilityLevel.everyone => 'Everyone',
        VisibilityLevel.contacts => 'My contacts',
        VisibilityLevel.nobody => 'Nobody',
      };

  static VisibilityLevel fromWire(String? s) => switch (s) {
        'contacts' => VisibilityLevel.contacts,
        'nobody' => VisibilityLevel.nobody,
        _ => VisibilityLevel.everyone,
      };
}

extension OnlineVisibilityX on OnlineVisibility {
  String get wire => switch (this) {
        OnlineVisibility.everyone => 'everyone',
        OnlineVisibility.sameAsLastSeen => 'same_as_last_seen',
      };

  String get label => switch (this) {
        OnlineVisibility.everyone => 'Everyone',
        OnlineVisibility.sameAsLastSeen => 'Same as Last seen',
      };

  static OnlineVisibility fromWire(String? s) =>
      s == 'same_as_last_seen'
          ? OnlineVisibility.sameAsLastSeen
          : OnlineVisibility.everyone;
}

extension GroupsWhoCanAddX on GroupsWhoCanAdd {
  String get wire => switch (this) {
        GroupsWhoCanAdd.everyone => 'everyone',
        GroupsWhoCanAdd.contacts => 'contacts',
      };

  String get label => switch (this) {
        GroupsWhoCanAdd.everyone => 'Everyone',
        GroupsWhoCanAdd.contacts => 'My contacts',
      };

  static GroupsWhoCanAdd fromWire(String? s) =>
      s == 'contacts' ? GroupsWhoCanAdd.contacts : GroupsWhoCanAdd.everyone;
}

class PrivacySettings {
  final VisibilityLevel lastSeenVisibility;
  final VisibilityLevel profilePhotoVisibility;
  final VisibilityLevel aboutVisibility;
  final OnlineVisibility onlineStatusVisibility;
  final GroupsWhoCanAdd groupsWhoCanAdd;
  final bool readReceipts;
  final bool callsSilenceUnknown;
  final bool appLockEnabled;
  final int appLockAutoLockMinutes; // 0 = Immediately

  const PrivacySettings({
    this.lastSeenVisibility = VisibilityLevel.everyone,
    this.profilePhotoVisibility = VisibilityLevel.everyone,
    this.aboutVisibility = VisibilityLevel.everyone,
    this.onlineStatusVisibility = OnlineVisibility.everyone,
    this.groupsWhoCanAdd = GroupsWhoCanAdd.everyone,
    this.readReceipts = true,
    this.callsSilenceUnknown = false,
    this.appLockEnabled = false,
    this.appLockAutoLockMinutes = 0,
  });

  factory PrivacySettings.fromJson(Map<String, dynamic> json) => PrivacySettings(
        lastSeenVisibility: VisibilityLevelX.fromWire(
          json['last_seen_visibility'] as String?,
        ),
        profilePhotoVisibility: VisibilityLevelX.fromWire(
          json['profile_photo_visibility'] as String?,
        ),
        aboutVisibility: VisibilityLevelX.fromWire(
          json['about_visibility'] as String?,
        ),
        onlineStatusVisibility: OnlineVisibilityX.fromWire(
          json['online_status_visibility'] as String?,
        ),
        groupsWhoCanAdd: GroupsWhoCanAddX.fromWire(
          json['groups_who_can_add'] as String?,
        ),
        readReceipts: json['read_receipts'] as bool? ?? true,
        callsSilenceUnknown: json['calls_silence_unknown'] as bool? ?? false,
        appLockEnabled: json['app_lock_enabled'] as bool? ?? false,
        appLockAutoLockMinutes:
            (json['app_lock_auto_lock_minutes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'last_seen_visibility': lastSeenVisibility.wire,
        'profile_photo_visibility': profilePhotoVisibility.wire,
        'about_visibility': aboutVisibility.wire,
        'online_status_visibility': onlineStatusVisibility.wire,
        'groups_who_can_add': groupsWhoCanAdd.wire,
        'read_receipts': readReceipts,
        'calls_silence_unknown': callsSilenceUnknown,
        'app_lock_enabled': appLockEnabled,
        'app_lock_auto_lock_minutes': appLockAutoLockMinutes,
      };

  PrivacySettings copyWith({
    VisibilityLevel? lastSeenVisibility,
    VisibilityLevel? profilePhotoVisibility,
    VisibilityLevel? aboutVisibility,
    OnlineVisibility? onlineStatusVisibility,
    GroupsWhoCanAdd? groupsWhoCanAdd,
    bool? readReceipts,
    bool? callsSilenceUnknown,
    bool? appLockEnabled,
    int? appLockAutoLockMinutes,
  }) =>
      PrivacySettings(
        lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
        profilePhotoVisibility:
            profilePhotoVisibility ?? this.profilePhotoVisibility,
        aboutVisibility: aboutVisibility ?? this.aboutVisibility,
        onlineStatusVisibility:
            onlineStatusVisibility ?? this.onlineStatusVisibility,
        groupsWhoCanAdd: groupsWhoCanAdd ?? this.groupsWhoCanAdd,
        readReceipts: readReceipts ?? this.readReceipts,
        callsSilenceUnknown: callsSilenceUnknown ?? this.callsSilenceUnknown,
        appLockEnabled: appLockEnabled ?? this.appLockEnabled,
        appLockAutoLockMinutes:
            appLockAutoLockMinutes ?? this.appLockAutoLockMinutes,
      );
}

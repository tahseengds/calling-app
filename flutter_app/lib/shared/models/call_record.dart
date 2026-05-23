import 'user.dart';

enum CallType { audio, video }

enum CallStatus { completed, missed, rejected }

class CallRecord {
  final String id;
  final CallType callType;
  final CallStatus status;
  final DateTime startedAt;
  final int? durationSeconds;
  final User otherUser;

  const CallRecord({
    required this.id,
    required this.callType,
    required this.status,
    required this.startedAt,
    this.durationSeconds,
    required this.otherUser,
  });

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
        id: json['id'] as String,
        callType: CallType.values.firstWhere(
          (e) => e.name == (json['call_type'] as String),
        ),
        status: CallStatus.values.firstWhere(
          (e) => e.name == (json['status'] as String),
        ),
        startedAt: DateTime.parse(json['started_at'] as String),
        durationSeconds: json['duration_seconds'] as int?,
        otherUser: User.fromJson(json['other_user'] as Map<String, dynamic>),
      );
}

import 'package:flutter_riverpod/legacy.dart';

class CallHistoryItem {
  final String id;
  final String name;
  final String direction; // 'in' or 'out'
  final String callType; // 'voice' or 'video'
  final String time;
  final String duration; // e.g. '12:04' or 'Missed'
  final bool isMissed;
  final bool isOnline;

  const CallHistoryItem({
    required this.id,
    required this.name,
    required this.direction,
    required this.callType,
    required this.time,
    required this.duration,
    this.isMissed = false,
    this.isOnline = false,
  });
}

class CallsNotifier extends StateNotifier<List<CallHistoryItem>> {
  CallsNotifier() : super(_initialData);

  static const _initialData = [
    CallHistoryItem(
      id: 'a',
      name: 'Grandma Rose',
      direction: 'in',
      callType: 'video',
      time: 'Just now',
      duration: '12:04',
      isOnline: true,
    ),
    CallHistoryItem(
      id: 'b',
      name: 'Dad Mike',
      direction: 'out',
      callType: 'voice',
      time: '15 min ago',
      duration: '4:12',
      isOnline: true,
    ),
    CallHistoryItem(
      id: 'c',
      name: 'Aunt Karen',
      direction: 'in',
      callType: 'voice',
      time: '1:42 PM',
      duration: 'Missed',
      isMissed: true,
    ),
    CallHistoryItem(
      id: 'd',
      name: 'Cousin Jamie',
      direction: 'out',
      callType: 'video',
      time: 'Yesterday',
      duration: '22:48',
    ),
    CallHistoryItem(
      id: 'e',
      name: 'Uncle Pete',
      direction: 'in',
      callType: 'voice',
      time: 'Yesterday',
      duration: '0:47',
    ),
    CallHistoryItem(
      id: 'f',
      name: 'Mom Sarah',
      direction: 'out',
      callType: 'video',
      time: 'Sunday',
      duration: '8:30',
      isOnline: true,
    ),
    CallHistoryItem(
      id: 'g',
      name: 'Grandma Rose',
      direction: 'in',
      callType: 'video',
      time: 'Sat',
      duration: 'Missed',
      isMissed: true,
    ),
  ];
}

final callsNotifierProvider = StateNotifierProvider<CallsNotifier, List<CallHistoryItem>>((ref) {
  return CallsNotifier();
});

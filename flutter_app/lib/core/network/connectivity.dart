import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityService {
  final _connectivity = Connectivity();

  Stream<bool> get onlineStream => _connectivity.onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );

  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
}

final connectivityProvider = Provider<ConnectivityService>(
  (_) => ConnectivityService(),
);

final isOnlineProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityProvider).onlineStream;
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';

class SupportRepository {
  final Dio _dio;
  SupportRepository(Dio dio) : _dio = dio;

  Future<void> submit({
    required String category,
    required String message,
    String? appVersion,
    String? platform,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final body = <String, dynamic>{
      'category': category,
      'message': message,
    };
    if (appVersion != null) body['app_version'] = appVersion;
    if (platform != null) body['platform'] = platform;
    if (deviceInfo != null) body['device_info'] = deviceInfo;

    await _dio.post<Map<String, dynamic>>(
      '/api/support/feedback',
      data: body,
    );
  }
}

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(ref.watch(dioProvider)),
);

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/models/user.dart';

class ProfileRepository {
  final Dio _dio;
  ProfileRepository(Dio dio) : _dio = dio;

  Future<User> getMe() async {
    final resp =
        await _dio.get<Map<String, dynamic>>('/api/users/me');
    return User.fromJson(resp.data!);
  }

  Future<User> updateName(String name) async {
    final resp = await _dio.patch<Map<String, dynamic>>(
      '/api/users/me',
      data: {'name': name},
    );
    return User.fromJson(resp.data!);
  }

  Future<User> updateAvatar(String filePath) async {
    final formData = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(filePath),
    });
    final resp = await _dio.patch<Map<String, dynamic>>(
      '/api/users/me',
      data: formData,
    );
    return User.fromJson(resp.data!);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(dioProvider)),
);

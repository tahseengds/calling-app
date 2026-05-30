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
    final resp = await _dio.put<Map<String, dynamic>>(
      '/api/users/me',
      data: {'name': name},
    );
    return User.fromJson(resp.data!);
  }

  Future<User> updateAvatar(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/users/avatar',
      data: formData,
    );
    return User.fromJson(resp.data!);
  }

  /// Permanently delete (anonymize) the signed-in account on the server.
  /// The backend revokes every session, so the caller must tear down local
  /// auth state afterwards.
  Future<void> deleteAccount() async {
    await _dio.delete<void>('/api/users/me');
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(dioProvider)),
);

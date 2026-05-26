import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/models/user.dart';

class ContactRepository {
  final Dio _dio;
  ContactRepository(Dio dio) : _dio = dio;

  Future<List<User>> getContacts() async {
    // Trailing slash is intentional — the backend route is mounted at
    // /api/contacts/, and hitting /api/contacts triggers a 307 redirect
    // which strips the Authorization header (Dio default).
    final resp = await _dio.get<List<dynamic>>('/api/contacts/');
    return (resp.data ?? [])
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [phone] must be E.164 (e.g. "+15550001234"). [nickname] is optional display name.
  Future<User> addContact({required String phone, String? nickname}) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/contacts/',
      // ignore: use_null_aware_elements
      data: {'phone': phone, if (nickname != null) 'nickname': nickname},
    );
    return User.fromJson(resp.data!);
  }

  Future<void> removeContact(String userId) =>
      _dio.delete('/api/contacts/$userId');
}

final contactRepositoryProvider = Provider<ContactRepository>(
  (ref) => ContactRepository(ref.watch(dioProvider)),
);

import 'dart:async';
import 'package:dio/dio.dart';

/// Attaches Bearer tokens to every outgoing request and handles 401 responses
/// by attempting a single token refresh. Concurrent 401s are serialized so
/// only one refresh call is made.
class TokenInterceptor extends Interceptor {
  final String? Function() getAccessToken;

  /// Returns true if the refresh succeeded and the new tokens have been saved.
  final Future<bool> Function() refreshTokens;

  /// Called when a refresh fails — should clear auth state and navigate to login.
  final void Function() onAuthExpired;

  // Non-null while a refresh is in flight; concurrent 401 waiters await this.
  Completer<bool>? _refreshCompleter;

  TokenInterceptor({
    required this.getAccessToken,
    required this.refreshTokens,
    required this.onAuthExpired,
  });

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final token = getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Avoid infinite loop if the refresh endpoint itself returns 401.
    if (err.requestOptions.path.contains('/api/auth/refresh')) {
      onAuthExpired();
      handler.next(err);
      return;
    }

    // Prevent double-retry on requests that were already replayed once.
    if (err.requestOptions.headers.containsKey('_retry')) {
      onAuthExpired();
      handler.next(err);
      return;
    }

    // FormData is a single-use byte stream — it is finalized on first send and
    // cannot be replayed. Refresh the token so the next request succeeds, then
    // reject this one. The caller must retry with a fresh FormData.
    final isMultipart = err.requestOptions.data is FormData;

    if (_refreshCompleter != null) {
      // Wait for the in-flight refresh to finish, then replay (or reject).
      final success = await _refreshCompleter!.future;
      if (success && !isMultipart) {
        handler.resolve(await _replay(err.requestOptions));
      } else {
        if (!success) onAuthExpired();
        handler.next(err);
      }
      return;
    }

    _refreshCompleter = Completer<bool>();
    bool success = false;
    try {
      success = await refreshTokens();
      _refreshCompleter!.complete(success);
    } catch (_) {
      _refreshCompleter!.complete(false);
    } finally {
      _refreshCompleter = null;
    }

    if (success && !isMultipart) {
      handler.resolve(await _replay(err.requestOptions));
    } else {
      if (!success) onAuthExpired();
      handler.next(err);
    }
  }

  Future<Response<dynamic>> _replay(RequestOptions original) {
    // Use a fresh Dio instance scoped to the base URL to replay the request.
    // The interceptor sets a fresh token in onRequest on the replayed call.
    final dio = Dio(BaseOptions(baseUrl: original.baseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (opts, handler) {
          final token = getAccessToken();
          if (token != null) opts.headers['Authorization'] = 'Bearer $token';
          opts.headers['_retry'] = 'true';
          handler.next(opts);
        },
      ),
    );
    return dio.request(
      original.path,
      data: original.data,
      queryParameters: original.queryParameters,
      options: Options(
        method: original.method,
        headers: original.headers,
        responseType: original.responseType,
        contentType: original.contentType,
      ),
    );
  }
}

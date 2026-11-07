import 'package:dio/dio.dart';

/// An error safe to present to users without exposing server URLs or secrets.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;

  static AppException fromNetwork(Object error) {
    if (error is AppException) {
      return error;
    }
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const AppException(
            'Connection timed out. Check the server and try again.',
          );
        case DioExceptionType.badCertificate:
          return const AppException('The server TLS certificate is invalid.');
        case DioExceptionType.connectionError:
          return const AppException('Could not connect to the server.');
        case DioExceptionType.cancel:
          return const AppException('The request was cancelled.');
        default:
          final status = error.response?.statusCode;
          return AppException(
            status == null
                ? 'The server returned an unexpected response.'
                : 'The server returned HTTP $status.',
          );
      }
    }
    return const AppException('An unexpected error occurred.');
  }
}

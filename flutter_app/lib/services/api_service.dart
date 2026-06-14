import 'dart:async';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../models/user.dart';
import '../models/trip.dart';
import 'storage_service.dart';

class ApiService {
  final StorageService _storage;
  late final Dio _dio;
  final Logger _logger = Logger();
  User? _cachedUser;
  final _unauthorizedController = StreamController<void>.broadcast();

  Stream<void> get onUnauthorized => _unauthorizedController.stream;

  static const String baseUrl = 'http://186.64.123.15:5000/api';

  ApiService(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptors
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        _logger.d('Request: ${options.method} ${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        _logger.d('Response: ${response.statusCode} ${response.data}');
        return handler.next(response);
      },
      onError: (error, handler) {
        _logger.e('Error: ${error.message}', error: error);
        return handler.next(error);
      },
    ));
  }

  // Auth
  Future<ApiResponse<User>> login({
    String? email,
    String? employeeId,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        if (email != null) 'email': email,
        if (employeeId != null) 'employeeId': employeeId,
        'password': password,
      });

      if (response.data['success'] == true) {
        final inner = response.data['data'] ?? {};
        final token = inner['token'];
        final userJson = inner['user'] ?? inner;
        final user = User.fromJson({
          ...Map<String, dynamic>.from(userJson),
          'token': token,
        });
        
        if (token != null) {
          await _storage.saveToken(token);
        }
        
        return ApiResponse.success(user);
      } else {
        return ApiResponse.error(
          response.data['message'] ?? 'Error en login',
        );
      }
    } on DioException catch (e) {
      return _handleDioError<User>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  Future<ApiResponse<User>> getMe() async {
    try {
      final response = await _dio.get('/auth/me');

      if (response.data['success'] == true) {
        final inner = response.data['data'];
        final userJson = inner is Map && inner.containsKey('user')
            ? inner['user']
            : inner;
        final user = User.fromJson(Map<String, dynamic>.from(userJson));
        return ApiResponse.success(user);
      } else {
        return ApiResponse.error(response.data['message'] ?? 'Error');
      }
    } on DioException catch (e) {
      return _handleDioError<User>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  // Trips
  Future<ApiResponse<Trip>> startTrip() async {
    try {
      final user = await getCachedUser();
      if (user == null) {
        return ApiResponse.error('Usuario no autenticado');
      }

      final response = await _dio.post('/deliveries/${user.id}/start');

      if (response.data['success'] == true) {
        final trip = Trip.fromJson(response.data['data']);
        return ApiResponse.success(trip);
      } else {
        return ApiResponse.error(response.data['message'] ?? 'Error iniciando viaje');
      }
    } on DioException catch (e) {
      return _handleDioError<Trip>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  Future<ApiResponse<Trip>> stopTrip() async {
    try {
      final user = await getCachedUser();
      if (user == null) {
        return ApiResponse.error('Usuario no autenticado');
      }

      final response = await _dio.post('/deliveries/${user.id}/stop');

      if (response.data['success'] == true) {
        final trip = Trip.fromJson(response.data['data']);
        return ApiResponse.success(trip);
      } else {
        return ApiResponse.error(response.data['message'] ?? 'Error deteniendo viaje');
      }
    } on DioException catch (e) {
      return _handleDioError<Trip>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  Future<ApiResponse<Trip?>> getActiveTrip() async {
    try {
      final response = await _dio.get('/deliveries/my-trip');

      if (response.data['success'] == true) {
        final inner = response.data['data'];
        final tripData = inner is Map ? (inner['trip'] ?? inner) : null;
        if (tripData != null && tripData['id'] != null) {
          final trip = Trip.fromJson(Map<String, dynamic>.from(tripData));
          return ApiResponse.success(trip);
        }
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(response.data['message'] ?? 'Error');
      }
    } on DioException catch (e) {
      return _handleDioError<Trip?>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  Future<ApiResponse<void>> updateLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
    int? batteryLevel,
  }) async {
    try {
      final user = await getCachedUser();
      if (user == null) {
        return ApiResponse.error('Usuario no autenticado');
      }

      final response = await _dio.post(
        '/deliveries/${user.id}/location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          if (accuracy != null) 'accuracy': accuracy,
          if (speed != null) 'speed': speed,
          if (heading != null) 'heading': heading,
          if (batteryLevel != null) 'batteryLevel': batteryLevel,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.data['success'] == true) {
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(response.data['message'] ?? 'Error');
      }
    } on DioException catch (e) {
      return _handleDioError<void>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  Future<ApiResponse<void>> updateMetrics({
    required int currentSpeed,
    required int averageSpeed,
    required int maxSpeed,
    required int totalDistanceM,
    required int totalTime,
    required int validLocations,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final user = await getCachedUser();
      if (user == null) {
        return ApiResponse.error('Usuario no autenticado');
      }

      final response = await _dio.post(
        '/deliveries/${user.id}/metrics',
        data: {
          'currentSpeed': currentSpeed,
          'averageSpeed': averageSpeed,
          'maxSpeed': maxSpeed,
          'totalDistanceM': totalDistanceM,
          'totalTime': totalTime,
          'validLocations': validLocations,
          'latitude': latitude,
          'longitude': longitude,
          'lastUpdate': DateTime.now().toIso8601String(),
        },
      );

      if (response.data['success'] == true) {
        return ApiResponse.success(null);
      } else {
        return ApiResponse.error(response.data['message'] ?? 'Error');
      }
    } on DioException catch (e) {
      return _handleDioError<void>(e);
    } catch (e) {
      return ApiResponse.error('Error de conexión');
    }
  }

  Future<User?> getCachedUser() async {
    _cachedUser ??= await _storage.getUser();
    return _cachedUser;
  }

  Future<String?> getToken() async {
    return await _storage.getToken();
  }

  void invalidateCache() {
    _cachedUser = null;
  }

  void dispose() {
    _unauthorizedController.close();
  }

  ApiResponse<T> _handleDioError<T>(DioException e) {
    if (e.response != null) {
      final statusCode = e.response?.statusCode;
      final message = e.response?.data?['message'] ?? 'Error del servidor';

      if (statusCode == 401) {
        _cachedUser = null;
        _unauthorizedController.add(null);
        return ApiResponse.error('Sesión expirada', code: 401);
      }

      return ApiResponse.error(message, code: statusCode);
    } else {
      return ApiResponse.error('Error de conexión');
    }
  }
}

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? code;

  const ApiResponse._({
    required this.success,
    this.data,
    this.error,
    this.code,
  });

  factory ApiResponse.success(T data) {
    return ApiResponse._(success: true, data: data);
  }

  factory ApiResponse.error(String error, {int? code}) {
    return ApiResponse._(success: false, error: error, code: code);
  }

  bool get hasError => !success;
  bool get isUnauthorized => code == 401;
}

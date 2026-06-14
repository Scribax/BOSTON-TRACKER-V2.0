import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';

// Keys used to pass config from UI isolate → foreground isolate
const _kUserId = 'fg_userId';
const _kToken = 'fg_token';
const _kBaseUrl = 'fg_baseUrl';
const _kDeliveryName = 'fg_deliveryName';

class ForegroundService {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'boston_tracker_location',
        channelName: 'Boston Tracker GPS',
        channelDescription: 'Rastreando ubicación en tiempo real',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Saves the credentials the foreground isolate needs to call the API.
  static Future<void> saveCredentials({
    required String userId,
    required String token,
    required String baseUrl,
    required String deliveryName,
  }) async {
    await FlutterForegroundTask.saveData(key: _kUserId, value: userId);
    await FlutterForegroundTask.saveData(key: _kToken, value: token);
    await FlutterForegroundTask.saveData(key: _kBaseUrl, value: baseUrl);
    await FlutterForegroundTask.saveData(key: _kDeliveryName, value: deliveryName);
  }

  /// Starts (or restarts) the foreground service.
  /// Credentials must be sent AFTER calling this via [sendCredentialsToTask].
  static Future<bool> startService({
    required String deliveryName,
    required String tripId,
  }) async {
    init();

    // If already running, just update the notification
    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('[ForegroundService] Already running — updating notification');
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Boston Tracker — En Ruta',
        notificationText: 'Rastreando a $deliveryName...',
      );
      return true;
    }

    // Retry up to 3 times — Android 14 ServiceTimeoutException is intermittent
    for (int attempt = 1; attempt <= 3; attempt++) {
      debugPrint('[ForegroundService] startService attempt $attempt...');
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'Boston Tracker — En Ruta',
        notificationText: 'Iniciando GPS para $deliveryName...',
        callback: startCallback,
      );
      if (result is ServiceRequestSuccess) {
        debugPrint('[ForegroundService] startService SUCCESS (attempt $attempt)');
        return true;
      }
      final err = (result as ServiceRequestFailure).error;
      debugPrint('[ForegroundService] startService FAILURE attempt $attempt: $err');
      // Even after a timeout, Android may have started the service anyway
      await Future.delayed(const Duration(milliseconds: 500));
      if (await FlutterForegroundTask.isRunningService) {
        debugPrint('[ForegroundService] Service is running despite timeout — OK');
        return true;
      }
      if (attempt < 3) await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Send credentials to a running foreground service isolate.
  static void sendCredentialsToTask({
    required String userId,
    required String token,
    required String baseUrl,
    required String deliveryName,
  }) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({
      'cmd': 'credentials',
      'userId': userId,
      'token': token,
      'baseUrl': baseUrl,
      'deliveryName': deliveryName,
    }));
  }

  static Future<void> updateNotification(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Boston Tracker — En Ruta',
        notificationText: text,
      );
    }
  }

  static Future<void> stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// Send a command to the foreground isolate (e.g. 'stop')
  static void sendCommand(String command) {
    FlutterForegroundTask.sendDataToTask(jsonEncode({'cmd': command}));
  }
}

// ─── Entry point for the foreground isolate ───────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

// ─── Task Handler — runs in its own Dart isolate ──────────────────────────────

class _LocationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionStream;
  Dio? _dio;

  String? _userId;
  String? _token;
  String? _baseUrl;

  Position? _lastPosition;
  double _totalDistanceKm = 0.0;
  double _maxSpeed = 0.0;
  final List<double> _speedSamples = [];
  int _validLocations = 0;
  DateTime? _startTime;
  DateTime? _lastSentTime;
  DateTime? _lastPositionReceived;
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  final List<_PendingLocation> _queue = [];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _userId = await FlutterForegroundTask.getData<String>(key: _kUserId);
    _token = await FlutterForegroundTask.getData<String>(key: _kToken);
    _baseUrl = await FlutterForegroundTask.getData<String>(key: _kBaseUrl);
    _startTime = DateTime.now();
    _lastPositionReceived = DateTime.now();

    debugPrint('[TaskHandler] onStart — userId=$_userId, hasToken=${_token != null}, baseUrl=$_baseUrl');

    _initDio();
    // Start GPS stream immediately — credentials may arrive shortly via onReceiveData
    _startGpsStream();
    _startHeartbeat();
    _startWatchdog();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _sendStatusToUi();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _heartbeatTimer?.cancel();
    _watchdogTimer?.cancel();
    await _positionStream?.cancel();
    _positionStream = null;
  }

  @override
  void onReceiveData(Object data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final cmd = map['cmd'] as String?;
      if (cmd == 'stop') {
        FlutterForegroundTask.stopService();
      } else if (cmd == 'flush') {
        _flushQueue();
      } else if (cmd == 'credentials' || cmd == 'updateCredentials') {
        _token = map['token'] as String?;
        _userId = map['userId'] as String?;
        _baseUrl = map['baseUrl'] as String? ?? _baseUrl;
        debugPrint('[TaskHandler] Credentials received — userId=$_userId, hasToken=${_token != null}');
        _initDio();
      }
    } catch (_) {}
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  void _initDio() {
    if (_baseUrl == null || _token == null) return;
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl!,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    ));
  }

  void _startGpsStream() {
    _positionStream?.cancel();
    // NOTE: No foregroundNotificationConfig here - we use flutter_foreground_task's notification only
    // to avoid conflicts with two foreground services running simultaneously
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
      intervalDuration: const Duration(seconds: 5),
    );
    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (_) {
      Future.delayed(const Duration(seconds: 5), _startGpsStream);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_lastPosition == null) return;
      final now = DateTime.now();
      if (_lastSentTime != null && now.difference(_lastSentTime!).inSeconds < 25) return;
      await _sendLocation(
        lat: _lastPosition!.latitude,
        lon: _lastPosition!.longitude,
        accuracy: _lastPosition!.accuracy,
        speed: 0,
        heading: _lastPosition!.heading,
      );
    });
  }

  void _startWatchdog() {
    _watchdogTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final elapsed = DateTime.now().difference(_lastPositionReceived ?? DateTime.now()).inSeconds;
      if (elapsed > 55) _startGpsStream();
    });
  }

  // ── GPS callback ───────────────────────────────────────────────────────────

  void _onPosition(Position p) async {
    _lastPositionReceived = DateTime.now();

    if (p.accuracy > 100) return; // too inaccurate

    _validLocations++;

    double distKm = 0;
    double speedKmh = 0;

    if (_lastPosition != null) {
      distKm = _haversine(
        _lastPosition!.latitude, _lastPosition!.longitude,
        p.latitude, p.longitude,
      );

      if (distKm * 1000 < 5) {
        _lastPosition = p;
        return;
      }

      final timeDiffHours = p.timestamp.difference(_lastPosition!.timestamp).inSeconds / 3600;
      if (timeDiffHours > 0) speedKmh = distKm / timeDiffHours;
      if (speedKmh > 120) return; // impossible speed

      _totalDistanceKm += distKm;
    }

    speedKmh = p.speed >= 0 ? p.speed * 3.6 : speedKmh;
    if (speedKmh > _maxSpeed) _maxSpeed = speedKmh;
    _speedSamples.add(speedKmh);
    if (_speedSamples.length > 10) _speedSamples.removeAt(0);
    final avgSpeed = _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;

    _lastPosition = p;

    final duration = DateTime.now().difference(_startTime!).inSeconds;
    final distM = (_totalDistanceKm * 1000).round();
    final distStr = distM >= 1000
        ? '${_totalDistanceKm.toStringAsFixed(2)} km recorridos'
        : '$distM m recorridos';

    // Update notification
    FlutterForegroundTask.updateService(
      notificationTitle: 'Boston Tracker — En Ruta',
      notificationText: '$distStr · ${speedKmh.round()} km/h',
    );

    // Send to backend (this isolate survives phone lock)
    await _sendLocation(
      lat: p.latitude,
      lon: p.longitude,
      accuracy: p.accuracy,
      speed: speedKmh,
      heading: p.heading,
    );
    await _sendMetrics(
      currentSpeed: speedKmh.round(),
      averageSpeed: avgSpeed.round(),
      maxSpeed: _maxSpeed.round(),
      totalDistanceM: distM,
      totalTime: duration,
      validLocations: _validLocations,
      lat: p.latitude,
      lon: p.longitude,
    );

    // Notify main isolate for UI updates
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'location',
      'lat': p.latitude,
      'lon': p.longitude,
      'speed': speedKmh,
      'heading': p.heading,
      'accuracy': p.accuracy,
      'totalDistanceKm': _totalDistanceKm,
      'durationSeconds': duration,
      'currentSpeed': speedKmh.round(),
      'averageSpeed': avgSpeed.round(),
      'maxSpeed': _maxSpeed.round(),
      'totalDistanceM': distM,
      'validLocations': _validLocations,
    }));
  }

  // ── HTTP helpers ───────────────────────────────────────────────────────────

  Future<void> _sendLocation({
    required double lat,
    required double lon,
    required double accuracy,
    required double speed,
    required double heading,
  }) async {
    if (_dio == null || _userId == null) return;
    // Flush queued first
    await _flushQueue();
    try {
      await _dio!.post('/deliveries/$_userId/location', data: {
        'latitude': lat,
        'longitude': lon,
        'accuracy': accuracy,
        'speed': speed,
        'heading': heading,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _lastSentTime = DateTime.now();
    } catch (e) {
      final code = _dioStatusCode(e);
      if (code == 404) {
        FlutterForegroundTask.stopService();
        return;
      }
      if (_queue.length < 500) {
        _queue.add(_PendingLocation(lat, lon, accuracy, speed, heading));
      }
    }
  }

  Future<void> _sendMetrics({
    required int currentSpeed,
    required int averageSpeed,
    required int maxSpeed,
    required int totalDistanceM,
    required int totalTime,
    required int validLocations,
    required double lat,
    required double lon,
  }) async {
    if (_dio == null || _userId == null) return;
    try {
      await _dio!.post('/deliveries/$_userId/metrics', data: {
        'currentSpeed': currentSpeed,
        'averageSpeed': averageSpeed,
        'maxSpeed': maxSpeed,
        'totalDistanceM': totalDistanceM,
        'totalTime': totalTime,
        'validLocations': validLocations,
        'latitude': lat,
        'longitude': lon,
        'lastUpdate': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _flushQueue() async {
    if (_queue.isEmpty || _dio == null || _userId == null) return;
    final batch = List<_PendingLocation>.from(_queue);
    for (final item in batch) {
      try {
        await _dio!.post('/deliveries/$_userId/location', data: {
          'latitude': item.lat,
          'longitude': item.lon,
          'accuracy': item.accuracy,
          'speed': item.speed,
          'heading': item.heading,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _queue.remove(item);
      } catch (_) {
        break; // still offline
      }
    }
  }

  void _sendStatusToUi() {
    if (_lastPosition == null) return;
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'status',
      'totalDistanceKm': _totalDistanceKm,
      'durationSeconds': DateTime.now().difference(_startTime!).inSeconds,
      'validLocations': _validLocations,
      'queueSize': _queue.length,
    }));
  }

  int? _dioStatusCode(Object e) {
    if (e is DioException) return e.response?.statusCode;
    return null;
  }

  // ── Math ───────────────────────────────────────────────────────────────────

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

class _PendingLocation {
  final double lat, lon, accuracy, speed, heading;
  _PendingLocation(this.lat, this.lon, this.accuracy, this.speed, this.heading);
}

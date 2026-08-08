import 'dart:async';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// LocationService handles GPS tracking and backend communication directly.
/// Geolocator's foregroundNotificationConfig keeps GPS alive when the phone is locked.
class LocationService {
  final ApiService _apiService;
  final Logger _logger = Logger();
  final Battery _battery = Battery();

  final _metricsController = StreamController<TripMetrics>.broadcast();
  Stream<TripMetrics> get metrics => _metricsController.stream;

  StreamSubscription<Position>? _positionStream;
  Timer? _metricsTimer;

  Position? _lastPosition;
  double _totalDistanceKm = 0.0;
  double _maxSpeed = 0.0;
  final List<double> _speedSamples = [];
  int _validLocations = 0;
  DateTime? _startTime;
  DateTime? _lastSentTime;
  int? _batteryLevel;
  Timer? _batteryTimer;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  LocationService(this._apiService);

  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    // Request battery optimizations exemption & notification permissions to prevent Android Doze Mode killing the app
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      _logger.w('Battery/Notification permission check warning: $e');
    }

    return true;
  }

  void startTracking({String? deliveryName}) {
    if (_isTracking) return;
    _isTracking = true;
    _startTime = DateTime.now();
    _totalDistanceKm = 0.0;
    _maxSpeed = 0.0;
    _speedSamples.clear();
    _validLocations = 0;
    _lastPosition = null;
    _lastSentTime = null;
    _batteryLevel = null;
    _startGpsStream(deliveryName: deliveryName);
    _startMetricsTimer();
    _refreshBatteryLevel();
    _startBatteryTimer();
    _logger.i('LocationService started (GPS + HTTP via Geolocator foreground service)');
  }

  void stopTracking() {
    if (!_isTracking) return;
    _isTracking = false;
    _positionStream?.cancel();
    _positionStream = null;
    _metricsTimer?.cancel();
    _metricsTimer = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _logger.i('LocationService stopped');
  }

  void flushQueue() {
    if (_lastPosition != null && _isTracking) {
      _sendMetrics(_lastPosition!);
    }
  }

  void _startGpsStream({String? deliveryName}) {
    _positionStream?.cancel();
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Boston Tracker — En Ruta 🍔',
        notificationText: deliveryName != null
            ? 'Rastreando a $deliveryName en tiempo real'
            : 'GPS activo en segundo plano (2s)',
        enableWifiLock: true,
      ),
    );
    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (e) {
      _logger.e('GPS stream error: $e — restarting in 3s');
      Future.delayed(const Duration(seconds: 3), () {
        if (_isTracking) _startGpsStream(deliveryName: deliveryName);
      });
    });
  }

  void _onPosition(Position p) {
    // Allow initial location fixes to have up to 150m accuracy for faster bootstrap
    final maxAccuracyAllowed = _validLocations < 3 ? 150.0 : 100.0;
    if (p.accuracy > maxAccuracyAllowed) return;

    double distKm = 0;
    double speedKmh = 0;
    bool isStationary = false;

    if (_lastPosition != null) {
      distKm = _haversine(
        _lastPosition!.latitude, _lastPosition!.longitude,
        p.latitude, p.longitude,
      );
      if (distKm * 1000 < 3) {
        isStationary = true;
      } else {
        final timeDiffHours =
            p.timestamp.difference(_lastPosition!.timestamp).inSeconds / 3600;
        if (timeDiffHours > 0) speedKmh = distKm / timeDiffHours;
        if (speedKmh > 130) return;
        _totalDistanceKm += distKm;
      }
    }

    speedKmh = p.speed >= 0 ? p.speed * 3.6 : speedKmh;
    if (speedKmh > _maxSpeed) _maxSpeed = speedKmh;
    
    if (!isStationary) {
      _speedSamples.add(speedKmh);
      if (_speedSamples.length > 10) _speedSamples.removeAt(0);
    }
    
    _validLocations++;
    _lastPosition = p;

    final avgSpeed = _speedSamples.isEmpty
        ? 0.0
        : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
    final durationSeconds = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;

    _metricsController.add(TripMetrics(
      currentSpeed: isStationary ? 0 : speedKmh.round(),
      averageSpeed: avgSpeed.round(),
      maxSpeed: _maxSpeed.round(),
      totalDistanceM: (_totalDistanceKm * 1000).round(),
      totalTime: durationSeconds,
      validLocations: _validLocations,
    ));

    // High frequency HTTP sends: 2s when moving, 5s heartbeat when stationary
    final now = DateTime.now();
    final minIntervalSeconds = isStationary ? 5 : 2;
    if (_lastSentTime != null &&
        now.difference(_lastSentTime!).inSeconds < minIntervalSeconds) return;
    _lastSentTime = now;

    final locationPayload = {
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracy': p.accuracy,
      'speed': isStationary ? 0.0 : speedKmh,
      'heading': p.heading,
      'batteryLevel': _batteryLevel,
      'timestamp': p.timestamp.toIso8601String(),
    };

    // Try sending location to API. If offline, buffer to queue and auto-flush on reconnect.
    _apiService.updateLocation(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      speed: isStationary ? 0.0 : speedKmh,
      heading: p.heading,
      batteryLevel: _batteryLevel,
    ).then((res) {
      if (res.success) {
        _flushPendingOfflineLocations();
      } else {
        _bufferOfflineLocation(locationPayload);
      }
    }).catchError((e) {
      _logger.w('Location HTTP send failed, saving to offline buffer: $e');
      _bufferOfflineLocation(locationPayload);
      return ApiResponse<void>.error('Network glitch');
    });
  }

  final List<Map<String, dynamic>> _offlineQueue = [];

  void _bufferOfflineLocation(Map<String, dynamic> payload) {
    if (_offlineQueue.length > 1000) _offlineQueue.removeAt(0);
    _offlineQueue.add(payload);
    _logger.i('Offline location buffered. Total queued: ${_offlineQueue.length}');
  }

  Future<void> _flushPendingOfflineLocations() async {
    if (_offlineQueue.isEmpty) return;
    _logger.i('Flushing ${_offlineQueue.length} offline locations to server...');
    final toFlush = List<Map<String, dynamic>>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final item in toFlush) {
      try {
        await _apiService.updateLocation(
          latitude: item['latitude'] as double,
          longitude: item['longitude'] as double,
          accuracy: item['accuracy'] as double,
          speed: item['speed'] as double,
          heading: item['heading'] as double,
          batteryLevel: item['batteryLevel'] as int?,
        );
      } catch (e) {
        _logger.w('Error flushing queued location: $e');
      }
    }
  }

  void _startMetricsTimer() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lastPosition != null && _isTracking) {
        _sendMetrics(_lastPosition!);
      }
    });
  }

  void _startBatteryTimer() {
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshBatteryLevel();
    });
  }

  Future<void> _refreshBatteryLevel() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      _logger.d('Battery level: $_batteryLevel%');
    } catch (e) {
      _logger.w('Unable to read battery level: $e');
    }
  }

  void _sendMetrics(Position p) {
    final avgSpeed = _speedSamples.isEmpty
        ? 0.0
        : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
    final durationSeconds = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;

    _apiService.updateMetrics(
      currentSpeed: (p.speed * 3.6).round(),
      averageSpeed: avgSpeed.round(),
      maxSpeed: _maxSpeed.round(),
      totalDistanceM: (_totalDistanceKm * 1000).round(),
      totalTime: durationSeconds,
      validLocations: _validLocations,
      latitude: p.latitude,
      longitude: p.longitude,
    ).catchError((e) {
      _logger.w('Metrics HTTP send failed silently: $e');
      return ApiResponse<void>.error('Network glitch');
    });
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * pi / 180;

  void dispose() {
    stopTracking();
    _metricsController.close();
  }
}

class TripMetrics {
  final int currentSpeed;
  final int averageSpeed;
  final int maxSpeed;
  final int totalDistanceM;
  final int totalTime;
  final int validLocations;

  TripMetrics({
    required this.currentSpeed,
    required this.averageSpeed,
    required this.maxSpeed,
    required this.totalDistanceM,
    required this.totalTime,
    required this.validLocations,
  });
}

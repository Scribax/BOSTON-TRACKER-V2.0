import 'dart:async';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'api_service.dart';

/// LocationService — handles GPS tracking and backend communication directly.
/// Uses Geolocator's foregroundNotificationConfig so its own Android foreground
/// service keeps GPS alive when the phone is locked, without relying on
/// flutter_foreground_task (which fails with ServiceTimeoutException on some devices).
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
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Boston Tracker — En Ruta',
        notificationText: deliveryName != null
            ? 'Rastreando a $deliveryName'
            : 'GPS activo',
        enableWifiLock: true,
      ),
    );
    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (e) {
      _logger.e('GPS stream error: $e — restarting in 5s');
      Future.delayed(const Duration(seconds: 5), () {
        if (_isTracking) _startGpsStream(deliveryName: deliveryName);
      });
    });
  }

  void _onPosition(Position p) {
    if (p.accuracy > 100) return;

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
      final timeDiffHours =
          p.timestamp.difference(_lastPosition!.timestamp).inSeconds / 3600;
      if (timeDiffHours > 0) speedKmh = distKm / timeDiffHours;
      if (speedKmh > 120) return;
      _totalDistanceKm += distKm;
    }

    speedKmh = p.speed >= 0 ? p.speed * 3.6 : speedKmh;
    if (speedKmh > _maxSpeed) _maxSpeed = speedKmh;
    _speedSamples.add(speedKmh);
    if (_speedSamples.length > 10) _speedSamples.removeAt(0);
    _validLocations++;
    _lastPosition = p;

    final avgSpeed = _speedSamples.isEmpty
        ? 0.0
        : _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
    final durationSeconds = _startTime != null
        ? DateTime.now().difference(_startTime!).inSeconds
        : 0;

    _metricsController.add(TripMetrics(
      currentSpeed: speedKmh.round(),
      averageSpeed: avgSpeed.round(),
      maxSpeed: _maxSpeed.round(),
      totalDistanceM: (_totalDistanceKm * 1000).round(),
      totalTime: durationSeconds,
      validLocations: _validLocations,
    ));

    // Throttle HTTP sends to max once every 5 seconds
    final now = DateTime.now();
    if (_lastSentTime != null &&
        now.difference(_lastSentTime!).inSeconds < 5) return;
    _lastSentTime = now;

    _apiService.updateLocation(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      speed: speedKmh,
      heading: p.heading,
      batteryLevel: _batteryLevel,
    );
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
    );
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

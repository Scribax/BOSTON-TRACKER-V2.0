import 'dart:async';
import 'dart:math' show pi, sin, cos, sqrt, atan2, pow;
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'api_service.dart';
import 'foreground_service.dart';

class LocationService {
  final ApiService _apiService;
  final Logger _logger = Logger();

  StreamSubscription<Position>? _positionStream;
  final _locationController = StreamController<LocationData>.broadcast();
  final _metricsController = StreamController<TripMetrics>.broadcast();

  Stream<LocationData> get locations => _locationController.stream;
  Stream<TripMetrics> get metrics => _metricsController.stream;

  bool _isTracking = false;
  Position? _lastPosition;
  double _totalDistance = 0.0;
  double _maxSpeed = 0.0;
  List<double> _speedSamples = [];
  DateTime? _startTime;
  int _validLocations = 0;
  DateTime? _lastMetricsSent;

  bool get isTracking => _isTracking;
  double get totalDistance => _totalDistance;
  int get durationSeconds => _startTime != null
      ? DateTime.now().difference(_startTime!).inSeconds
      : 0;

  String? _deliveryName;

  LocationService(this._apiService);

  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<bool> requestBackgroundPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // Request background permission
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
           permission == LocationPermission.whileInUse;
  }

  void startTracking({String? deliveryName}) async {
    if (_isTracking) return;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      _logger.e('Location permissions not granted');
      return;
    }

    _isTracking = true;
    _deliveryName = deliveryName;
    _totalDistance = 0.0;
    _maxSpeed = 0.0;
    _speedSamples = [];
    _validLocations = 0;
    _startTime = DateTime.now();
    _lastPosition = null;

    _logger.i('Started location tracking');

    // Start foreground service to prevent OS from killing the app
    await ForegroundService.startService(
      deliveryName: deliveryName ?? 'repartidor',
      tripId: '',
    );

    // Use medium accuracy + larger distanceFilter for older devices
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      intervalDuration: Duration(seconds: 5),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationText: 'Boston Tracker está usando tu ubicación',
        notificationTitle: 'Rastreo activo',
        enableWakeLock: true,
      ),
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onPositionUpdate, onError: (e) {
      _logger.e('Position stream error: $e');
    });
  }

  void stopTracking() {
    _isTracking = false;
    _positionStream?.cancel();
    _positionStream = null;
    _lastPosition = null;
    _logger.i('Stopped location tracking');
    ForegroundService.stopService();
  }

  void _onPositionUpdate(Position position) async {
    if (!_isTracking) return;

    // Filter low accuracy locations (more tolerant for older devices)
    if (position.accuracy > 100) {
      _logger.w('Low accuracy location ignored: ${position.accuracy}m');
      return;
    }

    _validLocations++;

    // Calculate distance from last position
    double distanceKm = 0;
    double instantSpeed = 0;

    if (_lastPosition != null) {
      distanceKm = _calculateDistance(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Filter small movements (GPS noise)
      if (distanceKm * 1000 < 5) {
        return;
      }

      // Calculate time difference
      final timeDiff = position.timestamp.difference(_lastPosition!.timestamp);
      final timeDiffHours = timeDiff.inSeconds / 3600;

      if (timeDiffHours > 0) {
        instantSpeed = distanceKm / timeDiffHours;
      }

      // Filter impossible speeds
      if (instantSpeed > 120) {
        _logger.w('Impossible speed ignored: ${instantSpeed.toStringAsFixed(1)} km/h');
        return;
      }

      _totalDistance += distanceKm;
    }

    // Update foreground notification with current metrics
    final distM = (_totalDistance * 1000).round();
    final distStr = distM >= 1000
        ? '${(_totalDistance).toStringAsFixed(2)} km'
        : '$distM m';
    ForegroundService.updateNotification('$distStr recorridos');

    // Update max speed
    final currentSpeed = position.speed >= 0 ? position.speed * 3.6 : 0.0; // Convert m/s to km/h
    if (currentSpeed > _maxSpeed) {
      _maxSpeed = currentSpeed;
    }

    // Calculate average speed
    _speedSamples.add(currentSpeed);
    if (_speedSamples.length > 10) {
      _speedSamples.removeAt(0);
    }
    final avgSpeed = _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;

    final duration = DateTime.now().difference(_startTime!).inSeconds;

    final locationData = LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: currentSpeed,
      heading: position.heading,
      timestamp: position.timestamp,
      totalDistanceKm: _totalDistance,
      durationSeconds: duration,
    );

    final metrics = TripMetrics(
      currentSpeed: currentSpeed.round(),
      averageSpeed: avgSpeed.round(),
      maxSpeed: _maxSpeed.round(),
      totalDistanceM: (_totalDistance * 1000).round(),
      totalTime: duration,
      validLocations: _validLocations,
    );

    _locationController.add(locationData);
    _metricsController.add(metrics);

    // Send to backend
    await _sendLocationToBackend(locationData);
    // Throttle metrics to every 5 seconds
    final now = DateTime.now();
    if (_lastMetricsSent == null ||
        now.difference(_lastMetricsSent!).inSeconds >= 5) {
      _lastMetricsSent = now;
      await _sendMetricsToBackend(metrics, position.latitude, position.longitude);
    }

    _lastPosition = position;
  }

  Future<void> _sendLocationToBackend(LocationData data) async {
    try {
      await _apiService.updateLocation(
        latitude: data.latitude,
        longitude: data.longitude,
        accuracy: data.accuracy,
        speed: data.speed,
        heading: data.heading,
      );
    } catch (e) {
      _logger.e('Failed to send location: $e');
    }
  }

  Future<void> _sendMetricsToBackend(
    TripMetrics metrics,
    double latitude,
    double longitude,
  ) async {
    try {
      await _apiService.updateMetrics(
        currentSpeed: metrics.currentSpeed,
        averageSpeed: metrics.averageSpeed,
        maxSpeed: metrics.maxSpeed,
        totalDistanceM: metrics.totalDistanceM,
        totalTime: metrics.totalTime,
        validLocations: metrics.validLocations,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      _logger.e('Failed to send metrics: $e');
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Earth's radius in km
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
              cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
              sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return R * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  void dispose() {
    stopTracking();
    _locationController.close();
    _metricsController.close();
  }
}

class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final double totalDistanceKm;
  final int durationSeconds;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.timestamp,
    required this.totalDistanceKm,
    required this.durationSeconds,
  });
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

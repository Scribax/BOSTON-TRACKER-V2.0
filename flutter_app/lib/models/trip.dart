import 'package:equatable/equatable.dart';

class Trip extends Equatable {
  final String id;
  final String deliveryId;
  final String? deliveryName;
  final DateTime startTime;
  final DateTime? endTime;
  final String status;
  final double mileage;
  final int duration;
  final double averageSpeed;
  final double? currentSpeed;
  final double? maxSpeed;
  final Map<String, dynamic>? realTimeMetrics;
  final List<LocationPoint>? locations;
  final String? notes;

  const Trip({
    required this.id,
    required this.deliveryId,
    this.deliveryName,
    required this.startTime,
    this.endTime,
    required this.status,
    this.mileage = 0.0,
    this.duration = 0,
    this.averageSpeed = 0.0,
    this.currentSpeed,
    this.maxSpeed,
    this.realTimeMetrics,
    this.locations,
    this.notes,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] ?? '',
      deliveryId: json['deliveryId'] ?? '',
      deliveryName: json['deliveryName'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      status: json['status'] ?? 'active',
      mileage: (json['mileage'] ?? 0.0).toDouble(),
      duration: json['duration'] ?? 0,
      averageSpeed: (json['averageSpeed'] ?? 0.0).toDouble(),
      currentSpeed: json['currentSpeed']?.toDouble(),
      maxSpeed: json['maxSpeed']?.toDouble(),
      realTimeMetrics: json['realTimeMetrics'],
      locations: json['locations'] != null
          ? (json['locations'] as List)
              .map((e) => LocationPoint.fromJson(e))
              .toList()
          : null,
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deliveryId': deliveryId,
      'deliveryName': deliveryName,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'status': status,
      'mileage': mileage,
      'duration': duration,
      'averageSpeed': averageSpeed,
      'currentSpeed': currentSpeed,
      'maxSpeed': maxSpeed,
      'realTimeMetrics': realTimeMetrics,
      'locations': locations?.map((e) => e.toJson()).toList(),
      'notes': notes,
    };
  }

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isPaused => status == 'paused';

  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String get formattedMileage {
    if (mileage >= 1) {
      return '${mileage.toStringAsFixed(2)} km';
    } else {
      return '${(mileage * 1000).toStringAsFixed(0)} m';
    }
  }

  @override
  List<Object?> get props => [
        id,
        deliveryId,
        deliveryName,
        startTime,
        endTime,
        status,
        mileage,
        duration,
        averageSpeed,
        currentSpeed,
        maxSpeed,
        realTimeMetrics,
        locations,
        notes,
      ];
}

class LocationPoint extends Equatable {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;
  final double? speed;
  final double? heading;
  final double? altitude;

  const LocationPoint({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
    this.speed,
    this.heading,
    this.altitude,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      accuracy: json['accuracy']?.toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      speed: json['speed']?.toDouble(),
      heading: json['heading']?.toDouble(),
      altitude: json['altitude']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': timestamp.toIso8601String(),
      'speed': speed,
      'heading': heading,
      'altitude': altitude,
    };
  }

  @override
  List<Object?> get props => [
        latitude,
        longitude,
        accuracy,
        timestamp,
        speed,
        heading,
        altitude,
      ];
}

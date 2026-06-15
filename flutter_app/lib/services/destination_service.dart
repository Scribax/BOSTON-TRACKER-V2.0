import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';

import '../models/delivery_destination.dart';
import 'storage_service.dart';

class DestinationService {
  final StorageService _storage;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();
  final _controller = StreamController<DeliveryDestination>.broadcast();
  void Function(Map<String, dynamic>)? _emitAck;

  Stream<DeliveryDestination> get destinations => _controller.stream;

  DestinationService(this._storage);

  void bindAckEmitter(void Function(Map<String, dynamic>) emitAck) {
    _emitAck = emitAck;
  }

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);
    _logger.i('DestinationService initialized');
  }

  Future<void> handleIncomingPayload(Map<String, dynamic> payload) async {
    _logger.i('Incoming destination payload: $payload');
    final destination = DeliveryDestination.fromJson(payload);
    await _storage.saveLastDestination(destination);
    _controller.add(destination);
    await _showNotification(destination);
    _emitAck?.call({
      'deliveryId': destination.deliveryId,
      'deliveryName': destination.deliveryName,
      'assignedAt': destination.assignedAt.toIso8601String(),
      'receivedAt': DateTime.now().toIso8601String(),
    });
    _logger.i('Destination stored and notification shown for ${destination.deliveryId}');
  }

  Future<void> _showNotification(DeliveryDestination destination) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'delivery_destination',
        'Delivery destination',
        channelDescription: 'Destination sent by admin',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notifications.show(
      destination.deliveryId.hashCode,
      'Nueva ubicación asignada',
      destination.label ?? destination.deliveryName,
      details,
      payload: jsonEncode(destination.toJson()),
    );
  }

  Future<bool> openInMaps(DeliveryDestination destination) async {
    _logger.i('Opening Maps for ${destination.latitude}, ${destination.longitude}');
    final label = destination.label ?? destination.deliveryName;
    final mapsUri = defaultTargetPlatform == TargetPlatform.android
        ? Uri.parse(
            'geo:${destination.latitude},${destination.longitude}?q=${destination.latitude},${destination.longitude}(${Uri.encodeComponent(label)})',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${destination.latitude},${destination.longitude}',
          );

    try {
      final launched = await launchUrl(
        mapsUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _logger.w('Could not launch Maps URI: $mapsUri');
      }
      return launched;
    } catch (e, st) {
      _logger.e('Failed to open Maps', error: e, stackTrace: st);
      return false;
    }
  }

  Future<DeliveryDestination?> getLastDestination() async {
    return _storage.getLastDestination();
  }

  void dispose() {
    _controller.close();
  }
}

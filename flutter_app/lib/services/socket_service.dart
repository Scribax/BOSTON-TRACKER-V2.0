import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:logger/logger.dart';
import 'dart:async';
import '../config/api_config.dart';

class SocketService {
  io.Socket? _socket;
  final Logger _logger = Logger();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  String? _lastUserId;
  String? _lastToken;
  void Function(Map<String, dynamic>)? onDeliveryDestinationAck;

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  void _joinDeliveryRoom() {
    final userId = _lastUserId;
    if (userId == null || userId.isEmpty) {
      _logger.w('Skipping join-delivery because userId is missing');
      return;
    }

    _socket?.emit('join-delivery', userId);
    _logger.i('Joined delivery room: delivery-$userId');
  }

  void connect(String userId, String token) {
    _lastUserId = userId;
    _lastToken = token;
    if (_socket != null && _socket!.connected) {
      _joinDeliveryRoom();
      _logger.w('Socket already connected');
      return;
    }

    _logger.i('Connecting to Socket.IO at ${ApiConfig.socketUrl}...');

    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          .setReconnectionAttempts(99999)
          .build(),
    );

    _socket!.onConnect((_) {
      _logger.i('Socket connected: ${_socket!.id}');
      _joinDeliveryRoom();
    });

    _socket!.onDisconnect((reason) {
      _logger.w('Socket disconnected: $reason');
    });

    _socket!.onConnectError((error) {
      _logger.e('Socket connection error: $error');
    });

    _socket!.onReconnect((attempt) {
      _logger.i('Socket reconnected after $attempt attempts');
      if (_lastToken != null) {
        _socket?.io.options?['auth'] = {'token': _lastToken};
      }
      _joinDeliveryRoom();
      _eventController.add({'type': 'networkRestored', 'data': {}});
    });

    // Trip events
    _socket!.on('tripStopped', (data) {
      _logger.i('Trip stopped remotely: $data');
      _eventController.add({'type': 'tripStopped', 'data': data});
    });

    _socket!.on('tripStarted', (data) {
      _logger.i('Trip started: $data');
      _eventController.add({'type': 'tripStarted', 'data': data});
    });

    _socket!.on('tripCompleted', (data) {
      _logger.i('Trip completed: $data');
      _eventController.add({'type': 'tripCompleted', 'data': data});
    });

    _socket!.on('deliveryDestination', (data) {
      _logger.i('Destination received: $data');
      _eventController.add({'type': 'deliveryDestination', 'data': data});
    });

    _socket!.on('deliveryDestinationAck', (data) {
      _logger.i('Destination ACK received: $data');
      _eventController.add({'type': 'deliveryDestinationAck', 'data': data});
    });

    _socket!.onAny((event, data) {
      _logger.d('Socket event: $event -> $data');
    });

    _socket!.on('notification', (data) {
      _logger.i('Notification: $data');
      _eventController.add({'type': 'notification', 'data': data});
    });

    _socket!.on('forceLogout', (data) {
      _logger.w('Force logout received: $data');
      _eventController.add({'type': 'forceLogout', 'data': data});
    });

    _socket!.connect();
  }

  void disconnect() {
    _logger.i('Disconnecting socket...');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class SocketService {
  io.Socket? _socket;
  final Logger _logger = Logger();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  String? _lastUserId;
  String? _lastToken;
  bool _wasOffline = false;

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void _listenConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        _wasOffline = true;
        _logger.w('Network lost');
      } else if (_wasOffline) {
        _wasOffline = false;
        _logger.i('Network restored — reconnecting socket');
        if (_lastUserId != null && _lastToken != null) {
          _socket?.disconnect();
          Future.delayed(const Duration(milliseconds: 500), () {
            connect(_lastUserId!, _lastToken!);
          });
        }
        _eventController.add({'type': 'networkRestored', 'data': {}});
      }
    });
  }

  void connect(String userId, String token) {
    _lastUserId = userId;
    _lastToken = token;
    _listenConnectivity();
    if (_socket != null && _socket!.connected) {
      _logger.w('Socket already connected');
      return;
    }

    _logger.i('Connecting to Socket.IO...');

    _socket = io.io(
      'http://186.64.123.15:5000',
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
      
      // Join delivery room
      _socket!.emit('join-delivery', userId);
      _logger.i('Joined delivery room: delivery-$userId');
    });

    _socket!.onDisconnect((reason) {
      _logger.w('Socket disconnected: $reason');
    });

    _socket!.onConnectError((error) {
      _logger.e('Socket connection error: $error');
    });

    _socket!.onReconnect((attempt) {
      _logger.i('Socket reconnected after $attempt attempts');
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
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}

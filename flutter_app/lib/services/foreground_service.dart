import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
        notificationText: 'Tracking activo para $deliveryName',
      );
      return true;
    }

    // Retry up to 3 times — Android 14 ServiceTimeoutException is intermittent
    for (int attempt = 1; attempt <= 3; attempt++) {
      debugPrint('[ForegroundService] startService attempt $attempt...');
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'Boston Tracker — En Ruta',
        notificationText: 'Manteniendo tracking en segundo plano para $deliveryName...',
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
      'cmd': 'updateMetadata',
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
  String? _deliveryName;
  DateTime? _startedAt;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _deliveryName = await FlutterForegroundTask.getData<String>(key: _kDeliveryName);
    _startedAt = DateTime.now();
    debugPrint('[TaskHandler] onStart — delivery=$_deliveryName');
    FlutterForegroundTask.updateService(
      notificationTitle: 'Boston Tracker — En Ruta',
      notificationText: _deliveryName != null
          ? 'Tracking activo para $_deliveryName'
          : 'Tracking activo en segundo plano',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.sendDataToMain(jsonEncode({
      'type': 'foregroundAlive',
      'startedAt': _startedAt?.toIso8601String(),
      'deliveryName': _deliveryName,
    }));
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
  }

  @override
  void onReceiveData(Object data) {
    try {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final cmd = map['cmd'] as String?;
      if (cmd == 'stop') {
        FlutterForegroundTask.stopService();
      } else if (cmd == 'updateMetadata') {
        _deliveryName = map['deliveryName'] as String? ?? _deliveryName;
        FlutterForegroundTask.updateService(
          notificationTitle: 'Boston Tracker — En Ruta',
          notificationText: _deliveryName != null
              ? 'Tracking activo para $_deliveryName'
              : 'Tracking activo en segundo plano',
        );
      }
    } catch (_) {}
  }
}

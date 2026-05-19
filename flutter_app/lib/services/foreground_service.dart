import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> startService({
    required String deliveryName,
    required String tripId,
  }) async {
    init();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Boston Tracker',
        notificationText: 'Rastreando a $deliveryName...',
      );
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Boston Tracker',
      notificationText: 'Rastreando a $deliveryName...',
      callback: startCallback,
    );
  }

  static Future<void> stopService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> updateNotification(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Boston Tracker — En Ruta',
        notificationText: text,
      );
    }
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

class _LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

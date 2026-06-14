import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'bloc/auth/auth_bloc.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'services/foreground_service.dart';
import 'services/destination_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground task (must be before runApp)
  ForegroundService.init();

  // Location permissions — required before GPS stream can open
  if (await Permission.locationWhenInUse.isDenied) {
    await Permission.locationWhenInUse.request();
  }
  // Background location ("Always allow") — needed to keep GPS when screen is locked
  if (await Permission.locationAlways.isDenied) {
    await Permission.locationAlways.request();
  }

  // Android 13+ requires POST_NOTIFICATIONS permission at runtime
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
  await FlutterForegroundTask.requestNotificationPermission();
  await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  
  // Initialize services
  final storageService = StorageService();
  await storageService.init();
  
  final apiService = ApiService(storageService);
  final destinationService = DestinationService(storageService);
  await destinationService.init();
  
  runApp(BostonTrackerApp(
    apiService: apiService,
    storageService: storageService,
    destinationService: destinationService,
  ));
}

class BostonTrackerApp extends StatefulWidget {
  final ApiService apiService;
  final StorageService storageService;
  final DestinationService destinationService;

  const BostonTrackerApp({
    super.key,
    required this.apiService,
    required this.storageService,
    required this.destinationService,
  });

  @override
  State<BostonTrackerApp> createState() => _BostonTrackerAppState();
}

class _BostonTrackerAppState extends State<BostonTrackerApp> {
  late final AuthBloc _authBloc;

  @override
  void initState() {
    super.initState();
    _authBloc = AuthBloc(widget.apiService, widget.storageService);
    _authBloc.add(AppStarted());
  }

  @override
  void dispose() {
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => _authBloc,
      child: WithForegroundTask(
        child: MaterialApp.router(
          title: 'Boston Tracker',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          routerConfig: AppRouter.createRouter(_authBloc),
        ),
      ),
    );
  }
}

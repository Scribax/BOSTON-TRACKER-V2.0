import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'bloc/auth/auth_bloc.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'services/foreground_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground task (must be before runApp)
  ForegroundService.init();
  await FlutterForegroundTask.requestNotificationPermission();
  
  // Initialize services
  final storageService = StorageService();
  await storageService.init();
  
  final apiService = ApiService(storageService);
  
  runApp(BostonTrackerApp(
    apiService: apiService,
    storageService: storageService,
  ));
}

class BostonTrackerApp extends StatelessWidget {
  final ApiService apiService;
  final StorageService storageService;

  const BostonTrackerApp({
    super.key,
    required this.apiService,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    final authBloc = AuthBloc(apiService, storageService)..add(AppStarted());
    return BlocProvider(
      create: (_) => authBloc,
      child: MaterialApp.router(
        title: 'Boston Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: AppRouter.createRouter(authBloc),
      ),
    );
  }
}

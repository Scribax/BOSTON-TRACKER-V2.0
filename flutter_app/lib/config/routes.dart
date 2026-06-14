import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth/auth_bloc.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/trip_screen.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  static GoRouter createRouter(AuthBloc authBloc) => GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;

      // Still loading - don't redirect, wait
      if (authState is AuthInitial || authState is AuthLoading) {
        return null;
      }
      
      // Not authenticated - only allow login
      if (authState is AuthUnauthenticated) {
        if (state.matchedLocation != '/') {
          return '/';
        }
        return null;
      }
      
      // Authenticated - don't allow login page
      if (authState is AuthAuthenticated && state.matchedLocation == '/') {
        return '/home';
      }
      
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/trip',
        builder: (context, state) => const TripScreen(),
      ),
    ],
  );
}

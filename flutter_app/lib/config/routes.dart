import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth/auth_bloc.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/trip_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final authState = context.read<AuthBloc>().state;

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

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AppStarted extends AuthEvent {}

class LoginRequested extends AuthEvent {
  final String employeeId;
  final String password;

  const LoginRequested({
    required this.employeeId,
    required this.password,
  });

  @override
  List<Object?> get props => [employeeId, password];
}

class LogoutRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthUnauthenticated extends AuthState {
  final String? error;

  const AuthUnauthenticated({this.error});

  @override
  List<Object?> get props => [error];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService _apiService;
  final StorageService _storageService;

  AuthBloc(this._apiService, this._storageService) : super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    
    try {
      final token = await _storageService.getToken();
      
      if (token != null) {
        final response = await _apiService.getMe();
        
        if (response.success && response.data != null) {
          await _storageService.saveUser(response.data!);
          emit(AuthAuthenticated(response.data!));
        } else {
          await _storageService.clearAll();
          emit(const AuthUnauthenticated());
        }
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (e) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final response = await _apiService.login(
        employeeId: event.employeeId,
        password: event.password,
      );
      
      if (response.success && response.data != null) {
        await _storageService.saveUser(response.data!);
        
        if (response.data!.token != null) {
          await _storageService.saveToken(response.data!.token!);
        }
        
        emit(AuthAuthenticated(response.data!));
      } else {
        emit(AuthUnauthenticated(error: response.error ?? 'Error de login'));
      }
    } catch (e) {
      emit(const AuthUnauthenticated(error: 'Error de conexión'));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    await _storageService.clearAll();
    emit(const AuthUnauthenticated());
  }
}

import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String name;
  final String? email;
  final String? employeeId;
  final String role;
  final String? phone;
  final bool isActive;
  final DateTime? lastLogin;
  final String? token;
  final String? refreshToken;
  final bool hasActiveTrip;
  final String? tripId;

  const User({
    required this.id,
    required this.name,
    this.email,
    this.employeeId,
    required this.role,
    this.phone,
    required this.isActive,
    this.lastLogin,
    this.token,
    this.refreshToken,
    this.hasActiveTrip = false,
    this.tripId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'],
      employeeId: json['employeeId'],
      role: json['role'] ?? 'delivery',
      phone: json['phone'],
      isActive: json['isActive'] ?? true,
      lastLogin: json['lastLogin'] != null
          ? DateTime.parse(json['lastLogin'])
          : null,
      token: json['token'],
      refreshToken: json['refreshToken'],
      hasActiveTrip: json['hasActiveTrip'] ?? false,
      tripId: json['tripId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'employeeId': employeeId,
      'role': role,
      'phone': phone,
      'isActive': isActive,
      'lastLogin': lastLogin?.toIso8601String(),
      'token': token,
      'refreshToken': refreshToken,
      'hasActiveTrip': hasActiveTrip,
      'tripId': tripId,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? employeeId,
    String? role,
    String? phone,
    bool? isActive,
    DateTime? lastLogin,
    String? token,
    String? refreshToken,
    bool? hasActiveTrip,
    String? tripId,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      employeeId: employeeId ?? this.employeeId,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      lastLogin: lastLogin ?? this.lastLogin,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      hasActiveTrip: hasActiveTrip ?? this.hasActiveTrip,
      tripId: tripId ?? this.tripId,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isDelivery => role == 'delivery';

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        employeeId,
        role,
        phone,
        isActive,
        lastLogin,
        token,
        refreshToken,
        hasActiveTrip,
        tripId,
      ];
}

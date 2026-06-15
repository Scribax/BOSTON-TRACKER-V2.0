import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/delivery_destination.dart';

class StorageService {
  late final SharedPreferences _prefs;
  final _secureStorage = const FlutterSecureStorage();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Token
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: 'token', value: token);
  }

  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: 'refreshToken', value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: 'token');
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: 'refreshToken');
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: 'token');
  }

  Future<void> deleteRefreshToken() async {
    await _secureStorage.delete(key: 'refreshToken');
  }

  // User
  Future<void> saveUser(User user) async {
    await _prefs.setString('user', jsonEncode(user.toJson()));
  }

  Future<User?> getUser() async {
    final userJson = _prefs.getString('user');
    if (userJson != null) {
      return User.fromJson(jsonDecode(userJson));
    }
    return null;
  }

  Future<void> deleteUser() async {
    await _prefs.remove('user');
  }

  // Trip Data
  Future<void> saveCurrentTrip(String tripJson) async {
    await _prefs.setString('currentTrip', tripJson);
  }

  Future<String?> getCurrentTrip() async {
    return _prefs.getString('currentTrip');
  }

  Future<void> deleteCurrentTrip() async {
    await _prefs.remove('currentTrip');
  }

  // Delivery destination
  Future<void> saveLastDestination(DeliveryDestination destination) async {
    await _prefs.setString('lastDestination', jsonEncode(destination.toJson()));
  }

  Future<DeliveryDestination?> getLastDestination() async {
    final raw = _prefs.getString('lastDestination');
    if (raw == null) return null;
    return DeliveryDestination.fromJson(jsonDecode(raw));
  }

  Future<void> deleteLastDestination() async {
    await _prefs.remove('lastDestination');
  }

  // Trip History
  Future<void> saveTripHistory(List<String> trips) async {
    await _prefs.setStringList('tripHistory', trips);
  }

  List<String> getTripHistory() {
    return _prefs.getStringList('tripHistory') ?? [];
  }

  Future<void> clearTripHistory() async {
    await _prefs.remove('tripHistory');
  }

  // Clear all
  Future<void> clearAll() async {
    await _prefs.clear();
    await _secureStorage.deleteAll();
  }
}

class ApiConfig {
  /// IP de tu computadora en la red Wi-Fi local: 192.168.1.36
  /// Cambia a '186.64.123.15' cuando subas el backend al servidor VPS de producción.
  static const String serverHost = '192.168.1.36';
  static const int serverPort = 5000;

  static String get baseUrl => 'http://$serverHost:$serverPort/api';
  static String get socketUrl => 'http://$serverHost:$serverPort';
}

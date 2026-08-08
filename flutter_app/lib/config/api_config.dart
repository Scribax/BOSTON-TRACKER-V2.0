class ApiConfig {
  /// IP Pública del VPS de Producción: 186.64.123.103
  static const String serverHost = '186.64.123.103';
  static const int serverPort = 5000;

  static String get baseUrl => 'http://$serverHost/api';
  static String get socketUrl => 'http://$serverHost';
}

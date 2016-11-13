import 'dart:io';

class Config {
  static InternetAddress get host => InternetAddress.ANY_IP_V4;

  static SecurityContext get securityContext => SecurityContext.defaultContext;
  static const bool useSsl = false;
  static const String sslCertificatePath = "";
  static const String sslKeyPath = '';
  static const String sslCertificatePassword = '';
  static const String sslKeyPassword = '';

  static const bool broadcast = false;
  static const String broadcastUrl = '?';

  static const int httpPort = 8123;
  static const int httpsPort = 8456;

  static const String downstreamName = 'downstream';
  static const Map<String, Map<String, dynamic>> upstream = null;

  static const String logLevel = 'info';
  static const bool quarantine = false;
  static const bool allowAllLinks = true;
}

import 'dart:io';
import 'dart:math';

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

  static int _port;
  static int httpPort =
      _port != null ? _port : _port = new Random.secure().nextInt(100) + 8010;
  static int get httpsPort => httpPort + 5;

  static const String downstreamName = 'downstream';
  static const Map<String, Map<String, dynamic>> upstream = null;

  static const String logLevel = 'info';
  static const bool quarantine = false;
  static const bool allowAllLinks = true;
}

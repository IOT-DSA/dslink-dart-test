import 'package:dsbroker/broker.dart';
import 'package:dslink/dslink.dart';
import 'package:dslink_dart_test/test_broker_node_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'src/config.dart';

class TestBroker {
  int httpPort;
  int httpsPort;
  TestBrokerNodeProvider broker;
  DsHttpServer server;
  BrokerDiscoveryClient discovery;
  SecurityContext context = SecurityContext.defaultContext;

  TestBroker(this.httpPort, this.httpsPort);

  Future<Null> start() async {
    var https = false;
    var config = JSON.decode(testBrokerConfig);

    dynamic getConfig(String key, [defaultValue]) {
      if (!config.containsKey(key)) {
        return defaultValue;
      }
      var value = config[key];

      if (value == null) {
        return defaultValue;
      }

      return value;
    }

    updateLogLevel(getConfig("logLevel", "finest"));
    var downstreamName = getConfig("downstreamName", "downstream");
    broker = new TestBrokerNodeProvider(downstreamName: downstreamName);

    server = new DsHttpServer.start(getConfig("host", "0.0.0.0"),
        httpPort: this.httpPort,
        httpsPort: this.httpsPort,
        nodeProvider: this.broker,
        linkManager: this.broker,
        sslContext: this.context);

    https = getConfig("httpsPort", -1) != -1;

    if (getConfig("broadcast", false)) {
      var addr = await getNetworkAddress();
      var scheme = https ? "https" : "http";
      var port = https ? getConfig("httpsPort") : getConfig("port");
      var url = getConfig("broadcastUrl", "$scheme://$addr:$port/conn");
      print("Starting Broadcast of Broker at $url");
      discovery = new BrokerDiscoveryClient();
      try {
        await discovery.init(true);
        discovery.requests.listen((BrokerDiscoverRequest request) {
          request.reply(url);
        });
      } catch (e) {
        print("Warning: Failed to start broker broadcast service."
            "Are you running more than one broker on this machine?");
      }
    }

    await broker.loadAll();

    if (getConfig("upstream") != null) {
      var upstream = getConfig("upstream", {}) as Map<String, Map<String, dynamic>>;
      for (var name in upstream.keys) {
        var upNode = upstream[name];
        var url = upNode["url"];
        var ourName = upNode["name"];
        var enabled = upNode["enabled"];
        var group = upNode["group"];
        broker.upstream
            .addUpstreamConnection(name, url, ourName, group, enabled);
      }
    }

    broker.upstream.onUpdate = (Map<Object, Object> map) async {
      config["upstream"] = map;
      //saveConfig();
    };

    broker.setConfigHandler = (String name, dynamic value) async {
      config[name] = value;
      //saveConfig();
    };
  }

  Future<Null> stop() async {
    await server.stop();

    Directory storageDir = new Directory("storage");
    if (storageDir.existsSync()) {
      storageDir.deleteSync(recursive: true);
    }
  }

  Future<String> getNetworkAddress() async {
    List<NetworkInterface> interfaces = await NetworkInterface.list();
    if (interfaces == null || interfaces.isEmpty) {
      throw new Exception("getNetworkAddress() has 0 NetworkInterfaces available");
      return null;
    }
    NetworkInterface interface = interfaces.first;
    List<InternetAddress> addresses = interface.addresses
        .where((it) => !it.isLinkLocal && !it.isLoopback)
        .toList();
    if (addresses.isEmpty) {
      throw new Exception("getNetworkAddress() has 0 InternetAddresses available");
      return null;
    }
    return addresses.first.address;
  }

  final String testBrokerConfig = const JsonEncoder.withIndent("  ").convert({
    "host": "0.0.0.0",
    "port": TEST_BROKER_HTTP_PORT,
    "httpsPort": TEST_BROKER_HTTPS_PORT,
    "downstreamName": "downstream",
    "logLevel": "finest",
    "quarantine": false,
    "allowAllLinks": true,
    "upstream": {},
    "sslCertificatePath": "",
    "sslKeyPath": "",
    "sslCertificatePassword": "",
    "sslKeyPassword": ""
  });
}

main() async {
  var broker = new TestBroker(TEST_BROKER_HTTP_PORT, TEST_BROKER_HTTPS_PORT);
  await broker.start();
}

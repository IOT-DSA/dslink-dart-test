import 'package:dsbroker/broker.dart';
import 'package:dslink/dslink.dart';
import 'package:dslink_dart_test/test_broker_node_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

class TestBroker {
  int httpPort;
  int httpsPort;
  TestBrokerNodeProvider broker;
  DsHttpServer server;
  BrokerDiscoveryClient discovery;
  SecurityContext context = SecurityContext.defaultContext;

  TestBroker(int httpPort, int httpsPort) {
    this.httpPort = httpPort;
    this.httpsPort = httpsPort;
  }

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

    server = new DsHttpServer.start(
        getConfig("host", "0.0.0.0"),
        httpPort: this.httpPort,
        httpsPort: this.httpsPort,
        nodeProvider: this.broker,
        linkManager: this.broker,
        sslContext: this.context
    );

    https = getConfig("httpsPort", -1) != -1;

    if (getConfig("broadcast", false)) {
      var addr = await getNetworkAddress();
      var scheme = https ? "https" : "http";
      var port = https ? getConfig("httpsPort") : getConfig("port");
      var url = getConfig("broadcastUrl", "${scheme}://${addr}:${port}/conn");
      print("Starting Broadcast of Broker at ${url}");
      discovery = new BrokerDiscoveryClient();
      try {
        await discovery.init(true);
        discovery.requests.listen((BrokerDiscoverRequest request) {
          request.reply(url);
        });
      } catch (e) {
        print(
            "Warning: Failed to start broker broadcast service."
                "Are you running more than one broker on this machine?");
      }
    }

    await broker.loadAll();

    if (getConfig("upstream") != null) {
      Map<String, Map<String, dynamic>> upstream = getConfig("upstream", {}) as Map<String, Map<String, dynamic>>;

      for (var name in upstream.keys) {
        var url = upstream[name]["url"];
        var ourName = upstream[name]["name"];
        var enabled = upstream[name]["enabled"];
        var group = upstream[name]["group"];
        broker.upstream.addUpstreamConnection(
            name,
            url,
            ourName,
            group,
            enabled
        );
      }
    }

    broker.upstream.onUpdate = (map) async {
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
    if (storageDir.existsSync())
    {
      storageDir.delete(recursive: true);
    }
  }

  Future<String> getNetworkAddress() async {
    List<NetworkInterface> interfaces = await NetworkInterface.list();
    if (interfaces == null || interfaces.isEmpty) {
      return null;
    }
    NetworkInterface interface = interfaces.first;
    List<InternetAddress> addresses = interface.addresses
        .where((it) => !it.isLinkLocal && !it.isLoopback)
        .toList();
    if (addresses.isEmpty) {
      return null;
    }
    return addresses.first.address;
  }

  final String testBrokerConfig = const JsonEncoder.withIndent("  ").convert({
    "host": "0.0.0.0",
    "port": 8123,
    "httpsPort": 8456,
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
  var broker = new TestBroker(8123, 8456);
  await broker.start();
}

import 'package:dsbroker/broker.dart';
import 'package:dslink/dslink.dart';
import 'package:dslink_dart_test/test_broker_node_provider.dart';
import 'dart:async';
import 'dart:io';
import 'src/config.dart';

class TestBroker {
  TestBrokerNodeProvider nodeProvider;
  DsHttpServer server;
  BrokerDiscoveryClient discovery;
  String brokerAddress;

  TestBroker();

  Future<Null> start() async {
    updateLogLevel(Config.logLevel);
    nodeProvider =
        new TestBrokerNodeProvider(downstreamName: Config.downstreamName);

    server = new DsHttpServer.start(Config.host,
        httpPort: Config.httpPort,
        httpsPort: Config.httpsPort,
        nodeProvider: this.nodeProvider,
        linkManager: this.nodeProvider,
        sslContext: Config.securityContext);

    var networkAddress = await _getNetworkAddress();
    var scheme = Config.useSsl ? "https" : "http";
    var port = Config.useSsl ? Config.httpsPort : Config.httpPort;
    brokerAddress = Config.broadcast
        ? Config.broadcastUrl
        : "$scheme://$networkAddress:$port/conn";

    if (Config.broadcast) {
      print("Starting Broadcast of Broker at $brokerAddress");

      discovery = new BrokerDiscoveryClient();
      try {
        await discovery.init(true);
        discovery.requests.listen((BrokerDiscoverRequest request) {
          request.reply(brokerAddress);
        });
      } catch (e) {
        print("Warning: Failed to start broker broadcast service."
            "Are you running more than one broker on this machine?");
      }
    }

    await nodeProvider.loadAll();

    var upstream = Config.upstream;
    if (upstream != null) {
      for (var name in upstream.keys) {
        var upstreamNode = upstream[name];
        var url = upstreamNode["url"];
        var ourName = upstreamNode["name"];
        var enabled = upstreamNode["enabled"];
        var group = upstreamNode["group"];
        nodeProvider.upstream
            .addUpstreamConnection(name, url, ourName, group, enabled);
      }
    }

    nodeProvider.upstream.onUpdate = (Map<Object, Object> map) async {
      Config.upstream["upstream"] = map;
    };

    nodeProvider.setConfigHandler =
        (String name, Map<String, dynamic> value) async {
      Config.upstream[name] = value;
    };
  }

  Future<Null> stop() async {
    await server.stop();

    Directory storageDir = new Directory("storage");
    if (storageDir.existsSync()) {
      storageDir.deleteSync(recursive: true);
    }
  }

  Future<String> _getNetworkAddress() async {
    List<NetworkInterface> interfaces = await NetworkInterface.list();
    if (interfaces == null || interfaces.isEmpty) {
      throw new Exception(
          "getNetworkAddress() has 0 NetworkInterfaces available");
    }
    NetworkInterface interface = interfaces.first;
    List<InternetAddress> addresses = interface.addresses
        .where((it) => !it.isLinkLocal && !it.isLoopback)
        .toList();
    if (addresses.isEmpty) {
      throw new Exception(
          "getNetworkAddress() has 0 InternetAddresses available");
    }
    return addresses.first.address;
  }
}

Future<Null> main() async {
  var broker = new TestBroker();
  await broker.start();
}

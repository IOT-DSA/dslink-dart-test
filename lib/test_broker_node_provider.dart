import 'package:dsbroker/broker.dart';
import 'package:dslink/responder.dart';
import 'dart:async';

class TestBrokerNodeProvider extends BrokerNodeProvider {
  TestBrokerNodeProvider(
      {enabledQuarantine: false,
      acceptAllConns: true,
      defaultPermission,
      downstreamName: "conns",
      IStorageManager storage,
      enabledDataNodes: true})
      : super(
            enabledQuarantine: enabledQuarantine,
            acceptAllConns: acceptAllConns,
            defaultPermission: defaultPermission,
            downstreamName: downstreamName,
            storage: storage,
            enabledDataNodes: enabledDataNodes);

  @override
  Future<Map> saveConns() async {
    print("Test Broker Mode -- Not Saving conns.json");
    return new Map();
  }
}

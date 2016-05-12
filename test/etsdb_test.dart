import 'package:test/test.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:dslink/requester.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';

main() {
  TestRequester testRequester;
  Requester requester;

  final String physicalLinkPath =
      '/home/joel/apps/dglux/dglux-server/dslinks/dslink-java-etsdb-0.0.4-SNAPSHOT';
  Process etsdbProcess;
  final String linkPath = '/downstream/etsdb';
  final String dbPath = 'dbPath';
  final String fullDbDirectoryPath = '$physicalLinkPath/$dbPath';

  Future deleteAndPurgeDatabase([bool failOnError = true]) async {
    String somePath = '$linkPath/$dbPath/dap';
    final invokeResult = requester.invoke(somePath);

    expect(new Directory(fullDbDirectoryPath).existsSync(), isFalse);

    if (!failOnError) {
      return;
    }

    final results = await invokeResult.toList();

    assertThatNoErrorHappened(results);

//    final nodesJsonFile = new File('$physicalLinkPath/nodes.json');
//    final decodedFile = await UTF8.decodeStream(nodesJsonFile.openRead());
//    final nodes = JSON.decode(decodedFile) as Map<String, dynamic>;

//    expect(nodes.containsKey(dbPath), isFalse);
  }

  setUp(() async {
    testRequester = new TestRequester();
    requester = await testRequester.start();
    etsdbProcess = await Process.start(
        'bin/dslink-java-etsdb', ['-b', 'http://localhost:8080/conn'],
        workingDirectory: physicalLinkPath);

    sleep(new Duration(seconds: 5));

    printProcessOutputs(etsdbProcess);
  });

  tearDown(() async {
    etsdbProcess.kill();
    testRequester.stop();
  });

  Future createDatabase() async {
    final invokeResult = requester
        .invoke('$linkPath/addDb', {'Name': 'myDB', 'Path': dbPath});

    assertThatNoErrorHappened(await invokeResult.toList());
  }

  test('should create db file when invoking the action', () async {
    await deleteAndPurgeDatabase(false);
    await createDatabase();

    final dbDirectory = new Directory(fullDbDirectoryPath);
    final directoryExists = dbDirectory.existsSync();
    expect(directoryExists, isTrue);
  });

  test('create watch group should create child wg node', () async {
    await deleteAndPurgeDatabase(false);
    await createDatabase();
    final watchGroupName = 'myWatchGroup';
    final invokeResult = await requester.invoke(
        '$linkPath/createWatchGroup', {'Name': watchGroupName}).toList();

    assertThatNoErrorHappened(invokeResult);

    final nodeValue = await requester
        .getNodeValue('$linkPath/$watchGroupName/\$\$$watchGroupName');
    expect(nodeValue.value, isTrue);
  });
}

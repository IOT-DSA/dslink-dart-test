import 'dart:async';
import 'dart:io';

import 'package:dslink/requester.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:test/test.dart';

void main() {
  TestRequester testRequester;
  Requester requester;
  Process etsdbProcess;
  Directory temporaryDirectory;

  Directory getLinksDirectory() {
    var path = '${Directory.current.path}/links';
    return new Directory(path);
  }

  final String linkName = 'dslink-java-etsdb-0.0.5-SNAPSHOT';
  final String distZipPath = "${getLinksDirectory().path}/$linkName.zip";
  final String linkPath = '/downstream/etsdb';
  final String dbPath = 'dbPath';

  String fullDbDirectoryPath() => '${temporaryDirectory.path}/$dbPath';

  setUp(() async {
    testRequester = new TestRequester();
    requester = await testRequester.start();

    temporaryDirectory = await createTempDirectoryFromDistZip(
        distZipPath, getLinksDirectory(), linkName);

    etsdbProcess = await Process.start(
        'bin/dslink-java-etsdb', ['-b', 'http://localhost:8080/conn'],
        workingDirectory: temporaryDirectory.path);
    sleep(new Duration(seconds: 1));

    printProcessOutputs(etsdbProcess);
  });

  tearDown(() async {
    etsdbProcess.kill();
    testRequester.stop();
    clearTestDirectory(temporaryDirectory);
  });

  Future createDatabase() async {
    final invokeResult =
        requester.invoke('$linkPath/addDb', {'Name': 'myDB', 'Path': dbPath});

    var updates = await invokeResult.toList();

    assertThatNoErrorHappened(updates);
  }

  test('should create db file when invoking the action', () async {
    await createDatabase();

    final dbDirectory = new Directory(fullDbDirectoryPath());
    final directoryExists = dbDirectory.existsSync();
    expect(directoryExists, isTrue);
  });

  test('create watch group should create child wg node', () async {
    await createDatabase();
    final watchGroupName = 'myWatchGroup';
    final invokeResult = await requester.invoke(
        '$linkPath/createWatchGroup', {'Name': watchGroupName}).toList();

    assertThatNoErrorHappened(invokeResult);

    final nodeValue = await requester
        .getNodeValue('$linkPath/$watchGroupName/\$\$$watchGroupName');
    expect(nodeValue.value, isTrue);
  }, skip: true);
}

import 'package:test/test.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:dslink/requester.dart';
import 'dart:io';
import 'dart:async';

main() {
  TestRequester testRequester;
  Requester requester;

  final String etsdbPath =
      '/home/joel/apps/dglux/dglux-server/dslinks/dslink-java-etsdb-0.0.4-SNAPSHOT';
  Process etsdbProcess;
  final String dbPath = 'dbPath';
  final String fullDbDirectoryPath = '$etsdbPath/$dbPath';

  Future purgeAndDeleteDatabase() async {
    final invokeResult =
        await requester.invoke('/downstream/etsdb/$dbPath/dap').toList();

    assertThatNoErrorHappened(invokeResult);

    expect(new Directory(fullDbDirectoryPath).existsSync(), isFalse);
  }

  setUp(() async {
    testRequester = new TestRequester();
    requester = await testRequester.start();
    etsdbProcess = await Process.start(
        'bin/dslink-java-etsdb', ['-b', 'http://localhost:8080/conn'],
        workingDirectory: etsdbPath);

    sleep(new Duration(seconds: 1));

    printProcessOutputs(etsdbProcess);

    await purgeAndDeleteDatabase();
  });

  tearDown(() async {
    etsdbProcess.kill();
    testRequester.stop();
  });

  test('should create db file when invoking the action', () async {
    final invokeResult = await requester.invoke(
        '/downstream/etsdb/addDb', {'Name': 'myDB', 'Path': dbPath}).toList();

    assertThatNoErrorHappened(invokeResult);

    final dbDirectory = new Directory(fullDbDirectoryPath);
    final directoryExists = dbDirectory.existsSync();
    expect(directoryExists, isTrue);
  });
}

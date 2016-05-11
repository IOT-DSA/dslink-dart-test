import 'package:test/test.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:dslink/requester.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() {
  TestResponder responder;
  TestRequester testRequester;
  Requester requester;
  Process etsdbProcess;
  final String etsdbPath =
      '/home/joel/apps/dglux/dglux-server/dslinks/dslink-java-etsdb-0.0.4-SNAPSHOT';

  setUp(() async {
    responder = new TestResponder();
    await responder.startResponder();

    testRequester = new TestRequester();
    requester = await testRequester.start();

    etsdbProcess = await Process.start(
        'bin/dslink-java-etsdb', ['-b', 'http://localhost:8080/conn'],
        workingDirectory: etsdbPath);

    sleep(new Duration(seconds: 1));

    etsdbProcess.stdout.listen((List<int> data) {
      final decoded = UTF8.decode(data);
      print(decoded);
    });

    etsdbProcess.stderr.listen((List<int> data) {
      final decoded = UTF8.decode(data);
      print(decoded);
    });
  });

  tearDown(() async {
    responder.stop();
    testRequester.stop();
    etsdbProcess.kill();
  });

  test('string value is the one expected', () async {
    final valueUpdate = await requester
        .getNodeValue('/downstream/TestResponder/sampleStringValue');

    expect(valueUpdate.value, 'sample text!');
  }, skip: true);

  group('action', () {
    test('should have a failure without params', () async {
      final invokeResult =
          await requester.invoke('/downstream/TestResponder/testAction');

      await for (final result in invokeResult) {
        expect(result.updates[0], [false, 'failure']);
      }
    });

    test('should have a success when good parameters input', () async {
      final invokeResult = await requester
          .invoke('/downstream/TestResponder/testAction', {'goodCall': true});

      await for (final result in invokeResult) {
        expect(result.updates[0], [true, 'success']);
      }
    });
  }, skip: true);

  group('etsdb', () {
    final String dbPath = 'dbPath';
    final String fullDbDirectoryPath = '$etsdbPath/$dbPath';

    Future purgeAndDeleteDatabase() async {
      final invokeResult =
          await requester.invoke('/downstream/etsdb/$dbPath/dap');

      await for (final result in invokeResult) {
        expect(result.error, isNull);
      }

      expect(new Directory(fullDbDirectoryPath).existsSync(), isFalse);
    }

    tearDown(() async {
      await purgeAndDeleteDatabase();
    });

    test('should create db file when invoking the action', () async {
      final invokeResult = await requester
          .invoke('/downstream/etsdb/addDb', {'Name': 'myDB', 'Path': dbPath});

      await for (final result in invokeResult) {
        expect(result.error, isNull);
      }

      final dbDirectory = new Directory(fullDbDirectoryPath);

      var directoryExists = dbDirectory.existsSync();
      expect(directoryExists, isTrue);
    });
  });
}

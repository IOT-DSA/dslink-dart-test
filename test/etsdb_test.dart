import 'dart:async';
import 'dart:io';

import 'package:dslink/requester.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:dslink_dart_test/test_broker.dart';
import 'package:test/test.dart';
import 'package:dslink/nodes.dart';

void main() {
  TestBroker testBroker;
  TestRequester testRequester;
  Requester requester;
  Process etsdbProcess;
  Directory temporaryDirectory;

  Directory getLinksDirectory() {
    final path = '${Directory.current.path}/links';
    return new Directory(path);
  }

  final String linkName = 'dslink-java-etsdb-0.0.5-SNAPSHOT';
  final String distZipPath = "${getLinksDirectory().path}/$linkName.zip";
  final String linkPath = '/downstream/etsdb';
  final String dbPath = 'dbPath';
  final String watchGroupName = 'myWatchGroup';
  final String watchGroupPath = '$linkPath/$dbPath/$watchGroupName';
  final String watchedPath = '/sys/version';

  String fullDbDirectoryPath() => '${temporaryDirectory.path}/$dbPath';

  setUp(() async {
    testBroker = new TestBroker(8123, 8456);
    await testBroker.start();

    testRequester = new TestRequester();
    requester = await testRequester.start();

    temporaryDirectory = await createTempDirectoryFromDistZip(
        distZipPath, getLinksDirectory(), linkName);

    etsdbProcess = await Process.start(
        'bin/dslink-java-etsdb', ['-b', 'http://localhost:8123/conn'],
        workingDirectory: temporaryDirectory.path);
    sleep(new Duration(seconds: 2));

    printProcessOutputs(etsdbProcess);
  });

  tearDown(() async {
    etsdbProcess.kill();

    sleep(new Duration(seconds: 2));
    clearTestDirectory(temporaryDirectory);

    final clearSysResult = requester.invoke('/sys/clearConns');
    await clearSysResult.toList();

    testRequester.stop();
    await testBroker.stop();
  });

  Future<Null> createWatch(
      String dbPath, String watchGroupName, String watchPath) async {
    final invokeResult = requester.invoke(
        '$linkPath/$dbPath/$watchGroupName/addWatchPath', {'Path': watchPath});

    final results = await invokeResult.toList();

    assertThatNoErrorHappened(results);
  }

  Future<Null> createWatchGroup(String watchGroupName) async {
    final invokeResult = requester
        .invoke('$linkPath/$dbPath/createWatchGroup', {'Name': watchGroupName});

    final results = await invokeResult.toList();

    assertThatNoErrorHappened(results);
  }

  Future createDatabase() async {
    final invokeResult =
        requester.invoke('$linkPath/addDb', {'Name': 'myDB', 'Path': dbPath});

    final updates = await invokeResult.toList();

    assertThatNoErrorHappened(updates);
  }

  test('create watch should create db directory', () async {
    await createDatabase();

    final dbDirectory = new Directory(fullDbDirectoryPath());
    final directoryExists = dbDirectory.existsSync();
    expect(directoryExists, isTrue);
  });

  group('with database', () {
    setUp(() async {
      await createDatabase();
    });

    test('create watch group should create child watchgroup node', () async {
      await createWatchGroup(watchGroupName);

      final nodeValue = await requester.getRemoteNode(watchGroupPath);

      expect(nodeValue.configs[r'$$wg'], isTrue);
    });

    group('with watch group', () {
      setUp(() async {
        await createWatchGroup(watchGroupName);
      });

      test('watches should be children of watch group', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final nodeValue = await requester.getRemoteNode(watchGroupPath);

        var encodedWatchPath = NodeNamer.createName(watchedPath);
        expect(nodeValue.children[encodedWatchPath], isNotNull);
      });

      test('@@getHistory should be added to the watched path', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final nodeValue = await requester.getRemoteNode(watchedPath);

        expect(nodeValue.attributes['@@getHistory'], isNotNull);
      });

      test('@@getHistory should be removed when delete and purge a watch',
          () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final watchPath =
            '$watchGroupPath/${NodeNamer.createName(watchedPath)}';
        final invokeResult = requester.invoke('$watchPath/unsubPurge');
        final results = await invokeResult.toList();

        assertThatNoErrorHappened(results);

        final nodeValue = await requester.getRemoteNode(watchedPath);

        expect(nodeValue.attributes['@@getHistory'], isNull);
      });
    });
  });
}

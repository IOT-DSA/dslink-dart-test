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

  final String linkName = 'dslink-java-etsdb-0.16.0-SNAPSHOT';
  final String distZipPath = "${getLinksDirectory().path}/$linkName.zip";
  final String linkPath = '/downstream/etsdb';
  final String dbPath = 'dbPath2';
  final String watchGroupName = 'myWatchGroup';
  final String watchGroupPath = '$linkPath/$dbPath/$watchGroupName';
  final String watchedPath = '/data/foo';

  String fullDbDirectoryPath() => '${temporaryDirectory.path}/$dbPath';

  Future<Null> startRequester() async {
    testRequester = new TestRequester();
    requester = await testRequester.start();
  }

  Future<Null> startBroker() async {
    testBroker = new TestBroker();
    await testBroker.start();
  }

  Future<Null> startLink() async {
    temporaryDirectory = await createTempDirectoryFromDistZip(
        distZipPath, getLinksDirectory(), linkName);

    etsdbProcess = await Process.start(
        'bin/dslink-java-etsdb', ['-b', testBroker.brokerAddress],
        workingDirectory: temporaryDirectory.path);
    await new Future.delayed(const Duration(seconds: 2));

    printProcessOutputs(etsdbProcess);
  }

  Future<Null> killLink() async {
    etsdbProcess.kill();

    await new Future.delayed(const Duration(seconds: 3));
    await clearTestDirectory(temporaryDirectory);

    final clearSysResult = requester.invoke('/sys/clearConns');
    await clearSysResult.toList();
  }

  Future<Null> killBroker() async {
    testRequester.stop();
    await testBroker.stop();
  }

  setUp(() async {
    await startBroker();
    await startRequester();
    await startLink();
  });

  tearDown(() async {
    await killLink();
    await killBroker();
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
    final directoryExists = await dbDirectory.exists();
    expect(directoryExists, isTrue);
  }, skip: false);

  group('with database', () {
    setUp(() async {
      await createDatabase();
    });

    test("paths with dots don't work when restarting etsdb", () async {
      final pathWithDot = 'a.b';
      await testRequester.setDataValue(pathWithDot, 12);

      await createWatchGroup(watchGroupName);
      await createWatch(dbPath, watchGroupName, pathWithDot);

      await testRequester.setDataValue(pathWithDot, 13);

      var update = await testRequester.getDataValue(pathWithDot);
      expect(update.value, 13);

      await killLink();

      await startLink();
      update = await testRequester.getDataValue(pathWithDot);
      expect(update.value, 13);

      await testRequester.setDataValue(pathWithDot, 14);
      update = await testRequester.getDataValue(pathWithDot);
      expect(update.value, 14);
    }, skip: false);

    test('create watch group should create child watchgroup node', () async {
      await createWatchGroup(watchGroupName);

      final nodeValue = await requester.getRemoteNode(watchGroupPath);

      expect(nodeValue.configs[r'$$wg'], isTrue);
    }, skip: false);

    group('with watch group', () {
      setUp(() async {
        await createWatchGroup(watchGroupName);
      });

      test('watches should be children of watch group', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final nodeValue = await requester.getRemoteNode(watchGroupPath);

        var encodedWatchPath = NodeNamer.createName(watchedPath);
        expect(nodeValue.children[encodedWatchPath], isNotNull);
      }, skip: false);

      test('@@getHistory should be added to the watched path', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final nodeValue = await requester.getRemoteNode(watchedPath);

        expect(nodeValue.attributes['@@getHistory'], isNotNull);
      }, skip: false);

      test('@@getHistory should return 1 value as ALL_DATA', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        await testRequester.setDataValue("foo", "bar");

        final watchPath =
            '$watchGroupPath/${NodeNamer.createName(watchedPath)}';

        final invokeResult = requester.invoke('$watchPath/getHistory');
        final results = await invokeResult.toList();

        assertThatNoErrorHappened(results);

        var updates =
            results.firstWhere((RequesterInvokeUpdate u) => u.updates != null);
        expect(updates.updates[0][1], equals("bar"));
      }, skip: false);

      test("@@getHistory should return multiple values as INTERVAL", () async {
        await testRequester.setDataValue("foo", "bar");
        await createWatch(dbPath, watchGroupName, watchedPath);
        await testRequester.setDataValue("foo", "bar2");

        final watchPath =
            '$watchGroupPath/${NodeNamer.createName(watchedPath)}';
        final editWatchGroup = requester.invoke('$watchGroupPath/edit', {
          "Logging Type": "Interval",
          "Interval": 1,
          "Buffer Flush Time": 1
        });
        final editWatchGroupResults = await editWatchGroup.toList();

        await new Future.delayed(const Duration(seconds: 5));

        final getHistory = requester.invoke('$watchPath/getHistory');
        final getHistoryResults = await getHistory.toList();

        assertThatNoErrorHappened(editWatchGroupResults);
        assertThatNoErrorHappened(getHistoryResults);
        var getHistoryUpdates = getHistoryResults
            .firstWhere((RequesterInvokeUpdate u) => u.updates != null);
        expect(getHistoryUpdates.updates.length, greaterThan(1));
      }, skip: false);

      test("@@getHistory interval values should be within threshold", () async {
        var interval = 1;
        await createWatch(dbPath, watchGroupName, watchedPath);
        await testRequester.setDataValue("foo", "bar");

        final watchPath =
            '$watchGroupPath/${NodeNamer.createName(watchedPath)}';
        final editResult = requester.invoke('$watchGroupPath/edit', {
          r"Logging Type": "Interval",
          r"Interval": interval,
          r"Buffer Flush Time": interval
        });
        final results = await editResult.toList();

        await new Future.delayed(const Duration(seconds: 10));

        final getHistoryResult = requester.invoke('$watchPath/getHistory');
        final history = await getHistoryResult.toList();

        var firstTime = DateTime.parse(history[1].updates.first[0]);

        var highDifference = 0;
        for (var update in history[1].updates) {
          var rawDate = DateTime.parse(update[0]);
          var difference = rawDate.difference(firstTime).inMilliseconds;

          while (difference > 500) {
            difference -= 1000;
          }

          if (difference.abs() > highDifference) {
            highDifference = difference.abs();
          }

          print("Difference: " +
              difference.toString() +
              ", rawDate: " +
              rawDate.toString());
        }

        assertThatNoErrorHappened(results);
        assertThatNoErrorHappened(history);
        expect(highDifference, lessThan(10));
      }, skip: false);

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
      }, skip: false);
    });
  });
}

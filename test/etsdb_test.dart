import 'dart:async';
import 'dart:io';

import 'dart:math';
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
  String watchedPath = '';
  String watchPath() =>
      '$watchGroupPath/${NodeNamer.createName('$watchedPath')}';
  final String typeAttribute = '\$type';

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

    watchedPath = '/data/$randomString';
  });

  tearDown(() async {
    await killLink();
    await killBroker();
  });

  Future<Null> createWatch(
      String dbPath, String watchGroupName, String watchedPath) async {
    final invokeResult = requester.invoke(
        '$linkPath/$dbPath/$watchGroupName/addWatchPath',
        {'Path': watchedPath});

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

      Future<RequesterInvokeUpdate> getHistoryUpdates(String watchPath) async {
        var getHistoryResult = requester.invoke('$watchPath/getHistory');
        var history = await getHistoryResult.toList();
        assertThatNoErrorHappened(history);
        return history
            .firstWhere((RequesterInvokeUpdate u) => u.updates != null);
      }

      test('@@getHistory should return 1 value as ALL_DATA', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        var newValue = new Random.secure().nextInt(1000).toString();
        await requester.set(watchedPath, newValue);

        var updates = await getHistoryUpdates(watchPath());

        expect(updates.updates[0][1], newValue);
      }, skip: false);

      test("@@getHistory should return multiple values as INTERVAL", () async {
        final loggingDurationInSeconds = 3;
        final intervalInSeconds = 1;
        await requester.set(watchedPath, "bar");
        await createWatch(dbPath, watchGroupName, watchedPath);

        final editWatchGroup = requester.invoke('$watchGroupPath/edit', {
          "Logging Type": "Interval",
          "Interval": intervalInSeconds,
          "Buffer Flush Time": 1
        });
        final editWatchGroupResults = await editWatchGroup.toList();
        assertThatNoErrorHappened(editWatchGroupResults);

        var purgeResult =
            await requester.invoke('${watchPath()}/purge').toList();
        assertThatNoErrorHappened(purgeResult);

        await new Future.delayed(
            new Duration(seconds: loggingDurationInSeconds));

        var result = await getHistoryUpdates(watchPath());
        // etsdb polling starts at 0 second
        expect(
            result.updates.length == loggingDurationInSeconds ||
                result.updates.length == loggingDurationInSeconds + 1,
            isTrue);
      }, skip: false);

      test("@@getHistory interval values should be within threshold", () async {
        var interval = 1;
        await createWatch(dbPath, watchGroupName, watchedPath);
        await requester.set(watchedPath, "bar");

        final editResult = requester.invoke('$watchGroupPath/edit', {
          r"Logging Type": "Interval",
          r"Interval": interval,
          r"Buffer Flush Time": interval
        });
        final results = await editResult.toList();

        await new Future.delayed(const Duration(seconds: 10));

        final getHistoryResult = requester.invoke('${watchPath()}/getHistory');
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

        final invokeResult = requester.invoke('${watchPath()}/unsubPurge');
        final results = await invokeResult.toList();

        assertThatNoErrorHappened(results);

        final nodeValue = await requester.getRemoteNode(watchedPath);

        expect(nodeValue.attributes['@@getHistory'], isNull);
      }, skip: false);

      test('logging should stop on child watches when deleting a watch group',
          () async {
        final initialValue = 42;
        final amountOfUpdates = 10;

        await requester.set(watchedPath, initialValue);
        await createWatch(dbPath, watchGroupName, watchedPath);
        var historyUpdates = await getHistoryUpdates(watchPath());
        expectHistoryUpdatesToOnlyContain(historyUpdates, initialValue);

        await unsubscribeWatchGroup(requester, watchPath);

        for (int i = 1; i <= amountOfUpdates; ++i) {
          await requester.set(watchedPath, initialValue + i);
        }

        await createWatch(dbPath, watchGroupName, watchedPath);
        historyUpdates = await getHistoryUpdates(watchPath());
        expect(historyUpdates.updates.length, 2);
        expect(historyUpdates.updates[0][1], initialValue);
        expect(historyUpdates.updates[1][1], initialValue + amountOfUpdates);
      }, skip: false);

      test('watch data type is set to dynamic when not explicitly set',
          () async {
        final initialValue = 'someValue';
        final secondValue = 12;

        await requester.set(watchedPath, initialValue);
        await requester.set(watchedPath, secondValue);
        await createWatch(dbPath, watchGroupName, watchedPath);

        var watchedNode = await requester.getRemoteNode(watchedPath);
        var watchedNodeType = watchedNode.get(typeAttribute);

        var watchNode = await requester.getRemoteNode(watchPath());
        var watchNodeType = watchNode.get(typeAttribute);

        expect(watchedNodeType, 'dynamic');
        expect(watchNodeType, 'dynamic');
      }, skip: false);

      test('watch data type is set to the type of the watched node', () async {
        final initialValue = 'hello';
        final expectedType = 'string';

        await requester.set(watchedPath, initialValue);
        await requester.set('$watchedPath/$typeAttribute', expectedType);
        await createWatch(dbPath, watchGroupName, watchedPath);

        var watchedNode = await requester.getRemoteNode(watchedPath);
        var watchedNodeType = watchedNode.get(typeAttribute);

        var watchNode = await requester.getRemoteNode(watchPath());
        var watchNodeType = watchNode.get(typeAttribute);

        expect(watchedNodeType, expectedType);
        expect(watchNodeType, expectedType);
      }, skip: false);

      test(
          'watch data type is set to given type when explicitly given even '
          'though the next values do not respect the type', () async {
        final initialValue = 'someValue';
        final secondValue = 12;
        final dataType = 'string';

        await requester.set(watchedPath, initialValue);
        await requester.set('$watchedPath/$typeAttribute', dataType);

        await createWatch(dbPath, watchGroupName, watchedPath);
        await requester.set(watchedPath, secondValue);

        var watch = await requester.getRemoteNode(watchPath());
        expect(watch.get(typeAttribute), dataType);
      }, skip: false);
    });
  });
}

void expectHistoryUpdatesToOnlyContain(
    RequesterInvokeUpdate historyUpdates, int initialValue) {
  expect(historyUpdates.updates.length, 1);
  expect(historyUpdates.updates[0][1], initialValue);
}

Future unsubscribeWatchGroup(Requester requester, String watchPath()) async {
  final invokeResult = requester.invoke('${watchPath()}/unsubscribe');
  final results = await invokeResult.toList();
  assertThatNoErrorHappened(results);
}

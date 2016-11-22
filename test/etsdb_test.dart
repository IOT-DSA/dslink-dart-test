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

  final String linkName = 'dslink-java-etsdb-0.17.0-SNAPSHOT';
  final String distZipPath = "${getLinksDirectory().path}/$linkName.zip";
  final String linkPath = '/downstream/etsdb';
  final String watchGroupName = 'myWatchGroup';
  String dbPath = 'willBeInitializedInSetup';
  String watchedPath = 'willBeInitializedInSetup';
  String watchGroupPath() => '$linkPath/$dbPath/$watchGroupName';
  String watchPath() =>
      '${watchGroupPath()}/${NodeNamer.createName('$watchedPath')}';
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
    await new Future.delayed(const Duration(seconds: 1));

    printProcessOutputs(etsdbProcess);
  }

  Future<Null> killLink({bool clearFiles: true}) async {
    etsdbProcess.kill();

    await new Future.delayed(const Duration(seconds: 3));

    if (clearFiles) {
      await clearTestDirectory(temporaryDirectory);

      await requester.invoke('/sys/clearConns').toList();
    }
  }

  Future<Null> killBroker() async {
    testRequester.stop();
    await testBroker.stop();
  }

  setUp(() async {
    await startBroker();
    await startRequester();
    await startLink();

    dbPath = randomString;
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
  }, skip: true);

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
    }, skip: true);

    test('create watch group should create child watchgroup node', () async {
      await createWatchGroup(watchGroupName);

      final nodeValue = await requester.getRemoteNode(watchGroupPath());

      expect(nodeValue.configs[r'$$wg'], isTrue);
    }, skip: true);

    group('with watch group', () {
      setUp(() async {
        await createWatchGroup(watchGroupName);
      });

      test('watches should be children of watch group', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final nodeValue = await requester.getRemoteNode(watchGroupPath());

        var encodedWatchPath = NodeNamer.createName(watchedPath);
        expect(nodeValue.children[encodedWatchPath], isNotNull);
      }, skip: true);

      test('watch should have all actions added on creation', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);
        await requester.set(watchedPath, 13);

        final unsubPurgeNode =
            await requester.getRemoteNode("${watchPath()}/unsubPurge");
        final getHistoryNode =
            await requester.getRemoteNode("${watchPath()}/getHistory");
        final unsubNode =
            await requester.getRemoteNode("${watchPath()}/unsubscribe");
        final purgeNode = await requester.getRemoteNode("${watchPath()}/purge");
        final overwriteHistory =
            await requester.getRemoteNode("${watchPath()}/overwriteHistory");

        expect(unsubPurgeNode.getConfig(r'$invokable'), 'config');
        expect(getHistoryNode.getConfig(r'$invokable'), 'read');
        expect(unsubNode.getConfig(r'$invokable'), 'config');
        expect(purgeNode.getConfig(r'$invokable'), 'config');
        expect(overwriteHistory.getConfig(r'$invokable'), 'config');
      }, skip: false);

      test('watch should have all actions added when link comes back up',
          () async {
        await createWatch(dbPath, watchGroupName, watchedPath);
        await requester.set(watchedPath, 13);
        await new Future.delayed(new Duration(
            seconds: 4)); // Make sure the value is written to the db.

        await killLink(clearFiles: false);
        await requester.invoke('/sys/clearConns').toList();
        await new Future.delayed(new Duration(seconds: 3));

        etsdbProcess = await Process.start(
            'bin/dslink-java-etsdb', ['-b', testBroker.brokerAddress],
            workingDirectory: temporaryDirectory.path);
        await new Future.delayed(const Duration(seconds: 5));
        printProcessOutputs(etsdbProcess);

        final unsubPurgeNode =
            await requester.getRemoteNode("${watchPath()}/unsubPurge");
        final getHistoryNode =
            await requester.getRemoteNode("${watchPath()}/getHistory");
        final unsubNode =
            await requester.getRemoteNode("${watchPath()}/unsubscribe");
        final purgeNode = await requester.getRemoteNode("${watchPath()}/purge");
        final overwriteHistory =
            await requester.getRemoteNode("${watchPath()}/overwriteHistory");

        expect(unsubPurgeNode.getConfig(r'$invokable'), 'config');
        expect(getHistoryNode.getConfig(r'$invokable'), 'read');
        expect(unsubNode.getConfig(r'$invokable'), 'config');
        expect(purgeNode.getConfig(r'$invokable'), 'config');
        expect(overwriteHistory.getConfig(r'$invokable'), 'config');
      }, skip: false);

      test('@@getHistory should be added to the watched path', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final nodeValue = await requester.getRemoteNode(watchedPath);

        expect(nodeValue.attributes['@@getHistory'], isNotNull);
      }, skip: true);

      Future<RequesterInvokeUpdate> getHistoryUpdates(String watchPath) async {
        var getHistoryResult = requester.invoke('$watchPath/getHistory');
        var history = await getHistoryResult.toList();
        assertThatNoErrorHappened(history);

        return history.firstWhere(
            (RequesterInvokeUpdate u) => u.updates != null,
            orElse: () => null);
      }

      test('@@getHistory should return 1 value as ALL_DATA', () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        var newValue = new Random.secure().nextInt(1000).toString();
        await requester.set(watchedPath, newValue);

        await new Future.delayed(new Duration(milliseconds: 400));
        var updates = await getHistoryUpdates(watchPath());

        expect(updates.updates[0][1], newValue);
      }, skip: true);

      test("@@getHistory should return multiple values as INTERVAL", () async {
        final loggingDurationInSeconds = 5;
        final intervalInSeconds = 1;
        await requester.set(watchedPath, "bar");
        await makeWatchGroupLogByInterval(
            requester, watchGroupPath(), intervalInSeconds);
        await createWatch(dbPath, watchGroupName, watchedPath);

        await new Future.delayed(
            new Duration(milliseconds: loggingDurationInSeconds * 1000 + 200));

        var result = await getHistoryUpdates(watchPath());
        expect(
            result.updates.length,
            inInclusiveRange(
                loggingDurationInSeconds, loggingDurationInSeconds + 1));
      }, skip: true);

      test(
          "@@getHistory should return multiple different values when logging "
          "in INTERVAL while the watched value changes between polls",
          () async {
        final loggingDurationInSeconds = 5;
        final intervalInSeconds = 1;
        await makeWatchGroupLogByInterval(
            requester, watchGroupPath(), intervalInSeconds);
        await createWatch(dbPath, watchGroupName, watchedPath);

        for (int i = 0; i < loggingDurationInSeconds; ++i) {
          await requester.set(watchedPath, i);
          await new Future.delayed(new Duration(seconds: intervalInSeconds));
        }

        var result = await getHistoryUpdates(watchPath());
        String previousTimeStamp;
        for (int i = 0; i < loggingDurationInSeconds; ++i) {
          expect(result.updates[i][0], isNot(previousTimeStamp));
          expect(result.updates[i][1], i);

          previousTimeStamp = result.updates[i][0];
        }
      }, skip: true);

      test("@@getHistory interval values should be within threshold", () async {
        var interval = 1;
        await createWatch(dbPath, watchGroupName, watchedPath);
        await requester.set(watchedPath, "bar");
        await makeWatchGroupLogByInterval(
            requester, watchGroupPath(), interval);

        await new Future.delayed(const Duration(seconds: 10));

        final getHistoryResult = requester.invoke('${watchPath()}/getHistory');
        final history = await getHistoryResult.toList();

        var previousTime = DateTime.parse(history[1].updates.first[0]);
        for (var update in history[1].updates.skip(1)) {
          var rawDate = DateTime.parse(update[0]);
          var difference = rawDate.difference(previousTime).inMilliseconds;

          expect(difference, lessThan(interval * 1000 * 1.15));

          previousTime = rawDate;
        }

        assertThatNoErrorHappened(history);
      }, skip: true);

      test('@@getHistory should be removed when delete and purge a watch',
          () async {
        await createWatch(dbPath, watchGroupName, watchedPath);

        final invokeResult = requester.invoke('${watchPath()}/unsubPurge');
        final results = await invokeResult.toList();

        assertThatNoErrorHappened(results);

        final nodeValue = await requester.getRemoteNode(watchedPath);

        expect(nodeValue.attributes['@@getHistory'], isNull);
      }, skip: true);

      test('logging should stop on child watches when deleting a watch group',
          () async {
        final initialValue = new Random.secure().nextInt(100);
        final amountOfUpdates = 10;

        await requester.set(watchedPath, initialValue);
        await createWatch(dbPath, watchGroupName, watchedPath);
        var historyUpdates = await getHistoryUpdates(watchPath());
        expectHistoryUpdatesToOnlyContain(historyUpdates, initialValue);

        await unsubscribeWatchGroup(requester, watchPath());

        for (int i = 1; i <= amountOfUpdates; ++i) {
          await requester.set(watchedPath, initialValue + i);
        }

        await createWatch(dbPath, watchGroupName, watchedPath);
        historyUpdates = await getHistoryUpdates(watchPath());
        expect(historyUpdates.updates.length, 2);
        expect(historyUpdates.updates[0][1], initialValue);
        expect(historyUpdates.updates[1][1], initialValue + amountOfUpdates);
      }, skip: true);

      test('watch data type is set to dynamic when not explicitly set',
          () async {
        final initialValue = 'someValue';
        final secondValue = 12;

        await requester.set(watchedPath, initialValue);
        await requester.set(watchedPath, secondValue);
        await createWatch(dbPath, watchGroupName, watchedPath);

        var watchedNodeType =
            await getNodeType(requester, watchedPath, typeAttribute);
        var watchNodeType =
            await getNodeType(requester, watchPath(), typeAttribute);

        expect(watchedNodeType, 'dynamic');
        expect(watchNodeType, 'dynamic');
      }, skip: true);

      test('watch data type is set to the type of the watched node', () async {
        final initialValue = 'hello';
        final expectedType = 'string';

        await requester.set(watchedPath, initialValue);
        await requester.set('$watchedPath/$typeAttribute', expectedType);
        await createWatch(dbPath, watchGroupName, watchedPath);

        var watchedNodeType =
            await getNodeType(requester, watchedPath, typeAttribute);
        var watchNodeType =
            await getNodeType(requester, watchPath(), typeAttribute);

        expect(watchedNodeType, expectedType);
        expect(watchNodeType, expectedType);
      }, skip: true);

      test(
          'watch data type is set to the type of the watched node even if '
          'last value is not of that type', () async {
        final initialValue = 12;
        final expectedType = 'string';

        await requester.set(watchedPath, initialValue);
        await requester.set('$watchedPath/$typeAttribute', expectedType);
        await createWatch(dbPath, watchGroupName, watchedPath);

        final watchedNodeType =
            await getNodeType(requester, watchedPath, typeAttribute);
        final watchNodeType =
            await getNodeType(requester, watchPath(), typeAttribute);

        expect(watchedNodeType, expectedType);
        expect(watchNodeType, expectedType);
      }, skip: true);

      group('override type', () {
        test('changes watch type with a provided one', () async {
          final initialValue = 12;
          final initialType = 'dynamic';
          final typeOverride = 'map';

          await requester.set(watchedPath, initialValue);
          await createWatch(dbPath, watchGroupName, watchedPath);
          var watchType =
              await getNodeType(requester, watchPath(), typeAttribute);
          expect(watchType, initialType);

          await overrideWatchType(requester, watchPath, typeOverride);

          watchType = await getNodeType(requester, watchPath(), typeAttribute);
          expect(watchType, typeOverride);
        }, skip: true);

        test('keeps type the same when typename is null', () async {
          final initialValue = 12;
          final initialType = 'dynamic';
          final typeOverride = null;

          await requester.set(watchedPath, initialValue);
          await createWatch(dbPath, watchGroupName, watchedPath);
          var watchType =
              await getNodeType(requester, watchPath(), typeAttribute);
          expect(watchType, initialType);

          await overrideWatchType(requester, watchPath, typeOverride);

          watchType = await getNodeType(requester, watchPath(), typeAttribute);
          expect(watchType, initialType);
        }, skip: true);

        test('keeps type the same when typeOverride is none', () async {
          final initialValue = 12;
          final initialType = 'dynamic';
          final typeOverride = 'none';

          await requester.set(watchedPath, initialValue);
          await createWatch(dbPath, watchGroupName, watchedPath);
          var watchType =
              await getNodeType(requester, watchPath(), typeAttribute);
          expect(watchType, initialType);

          await overrideWatchType(requester, watchPath, typeOverride);

          watchType = await getNodeType(requester, watchPath(), typeAttribute);
          expect(watchType, initialType);
        }, skip: true);
      });
    });
  });
}

Future<String> getNodeType(
    Requester requester, String nodePath, String typeAttribute) async {
  var node = await requester.getRemoteNode(nodePath);
  var nodeType = node.get(typeAttribute);
  return nodeType;
}

Future makeWatchGroupLogByInterval(
    Requester requester, String watchGroupPath, int intervalInSeconds) async {
  final editWatchGroup = requester.invoke('$watchGroupPath/edit', {
    "Logging Type": "Interval",
    "Interval": intervalInSeconds,
    "Buffer Flush Time": intervalInSeconds
  });
  final editWatchGroupResults = await editWatchGroup.toList();
  assertThatNoErrorHappened(editWatchGroupResults);
}

Future overrideWatchType(
    Requester requester, String watchPath(), String newType) async {
  var invokeResult = await requester
      .invoke('${watchPath()}/overrideType', {'TypeName': newType}).toList();

  assertThatNoErrorHappened(invokeResult);
}

void expectHistoryUpdatesToOnlyContain(
    RequesterInvokeUpdate historyUpdates, int initialValue) {
  expect(historyUpdates.updates.length, 1);
  expect(historyUpdates.updates[0][1], initialValue);
}

Future unsubscribeWatchGroup(Requester requester, String watchPath) async {
  final invokeResult = requester.invoke('$watchPath/unsubscribe');
  final results = await invokeResult.toList();
  assertThatNoErrorHappened(results);
}

import 'package:dslink/requester.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:dslink_dart_test/test_broker.dart';
import 'package:test/test.dart';

void main() {
  TestRequester testRequester;
  TestBroker testBroker;
  Requester requester;

  setUpAll(() async {
    testBroker = new TestBroker();
    await testBroker.start();

    testRequester = new TestRequester();
    requester = await testRequester.start();
  });

  tearDownAll(() async {
    testRequester.stop();
    await testBroker.stop();
  });

  group('SDK/Test Responder/Test Requester', () {
    TestResponder responder;

    setUp(() async {
      responder = new TestResponder();
      await responder.startResponder();
    });

    tearDown(() {
      responder.stop();
    });

    test('string value is the one expected', () async {
      final valueUpdate = await requester
          .getNodeValue('/downstream/TestResponder/sampleStringValue');

      expect(valueUpdate.value, 'sample text!');
    });

    test('should have a success adding and removing a node', () async {
      await testRequester.setDataValue("foo", "bar");

      final valueUpdate = await testRequester.getDataValue("foo");

      expect(valueUpdate.value, "bar");
    });

    group('action', () {
      test('should have a failure without params', () async {
        final invokeResult =
            requester.invoke('/downstream/TestResponder/testAction');

        final results = await invokeResult.toList();

        assertThatNoErrorHappened(results);

        for (final result in results) {
          expect(result.updates[0], [false, 'failure']);
        }
      });

      test('should have a success when good parameters input', () async {
        final invokeResult = requester
            .invoke('/downstream/TestResponder/testAction', {'goodCall': true});

        final results = await invokeResult.toList();

        assertThatNoErrorHappened(results);

        for (final result in results) {
          expect(result.updates[0], [true, 'success']);
        }
      });
    });
  });
}

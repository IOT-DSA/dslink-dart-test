import 'package:dslink/requester.dart';
import 'package:dslink_dart_test/dslink_test_framework.dart';
import 'package:test/test.dart';

void main() {
  TestRequester testRequester;
  Requester requester;

  setUpAll(() async {
    testRequester = new TestRequester();
    requester = await testRequester.start();
  });

  tearDownAll(() async {
    testRequester.stop();
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

    group('action', () {
      test('should have a failure without params', () async {
        final invokeResult = await requester
            .invoke('/downstream/TestResponder/testAction')
            .toList();

        assertThatNoErrorHappened(invokeResult);

        for (final result in invokeResult) {
          expect(result.updates[0], [false, 'failure']);
        }
      });

      test('should have a success when good parameters input', () async {
        final invokeResult = await requester.invoke(
            '/downstream/TestResponder/testAction',
            {'goodCall': true}).toList();

        assertThatNoErrorHappened(invokeResult);

        for (final result in invokeResult) {
          expect(result.updates[0], [true, 'success']);
        }
      });
    });
  });
}

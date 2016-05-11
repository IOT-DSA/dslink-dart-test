import 'dart:async';
import 'package:dslink/dslink.dart';

class TestAction extends SimpleNode {
  TestAction(String path) : super(path);

  static String isType = 'TestAction';

  static Map<String, dynamic> definition() => {
        r'$is': isType,
        r'$name': 'test action',
        r'$invokable': 'write',
        r'$columns': [
          {'name': 'success', 'type': 'bool', 'default': false},
          {'name': 'message', 'type': 'string', 'default': ''}
        ]
      };

  @override
  dynamic onInvoke(Map<String, dynamic> params) {
    params['goodCall'] = params['goodCall'] ?? false;

    final result = <String, dynamic>{'success': false, 'message': 'failure'};

    if (params['goodCall']) {
      result['success'] = true;
      result['message'] = 'success';
    }

    return result;
  }
}

class SampleStringValue extends SimpleNode {
  static String isType = 'SampleStringValue';

  SampleStringValue(String path) : super(path);

  static Map<String, dynamic> definition() => {
        r'$is': isType,
        r'$type': 'string',
        r'$name': 'sample string value',
        '?value': 'sample text!'
      };
}

class TestResponder {
  LinkProvider _linkProvider;

  Future<Null> startResponder() async {
    _linkProvider =
        new LinkProvider(['-b', 'http://localhost:8080/conn'], 'TestResponder',
            isRequester: false,
            isResponder: true,
            profiles: {
              TestAction.isType: (String path) => new TestAction(path),
              SampleStringValue.isType: (String path) =>
                  new SampleStringValue(path)
            });

    await _linkProvider.connect();
    _linkProvider.addNode('/testAction', TestAction.definition());
    _linkProvider.addNode('/sampleStringValue', SampleStringValue.definition());
  }

  void stop() => _linkProvider.stop();
}

class TestRequester {
  LinkProvider _linkProvider;

  Future<Requester> start() async {
    _linkProvider = new LinkProvider(
        ['-b', 'http://localhost:8080/conn'], 'TestRequester',
        isRequester: true, isResponder: false);

    _linkProvider.connect();

    final requester = await _linkProvider.onRequesterReady;
    return requester;
  }

  void stop() => _linkProvider.stop();
}

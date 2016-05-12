import 'package:dslink/dslink.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<Null> assertThatNoErrorHappened(
    List<RequesterInvokeUpdate> updates) async {
  for (final update in updates) {
    var error = update.error;
    if (error != null) {
      print(error.detail);
      print(error.getMessage());
    }
    expect(error, isNull);
  }
}

void printProcessOutputs(Process process) {
  final printOutputToConsole = (Stream<List<int>> data) async {
    await for (final encoded in data) {
      final decoded = UTF8.decode(encoded);
      print(decoded);
    }
  };

  printOutputToConsole(process.stdout);
  printOutputToConsole(process.stderr);
}

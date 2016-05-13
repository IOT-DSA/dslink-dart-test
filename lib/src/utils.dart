import 'package:dslink/dslink.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

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

Future extractZipArchive(
    Archive archive, String extractDirectory, String linkName) async {
  for (ArchiveFile file in archive) {
    String filename = file.name.replaceFirst(linkName, '');
    List<int> data = file.content;

    if (filename.endsWith('/')) {
      final directory = new Directory('$extractDirectory/$filename');
      await directory.create();
    } else {
      final file = new File('$extractDirectory/$filename');
      await file.create();
      await file.writeAsBytes(data);

      if (filename.startsWith('/bin/') &&
          (Platform.isLinux || Platform.isMacOS)) {
        var workingDirectoryPath =
            removeFileNamePathSegment('$extractDirectory$filename');
        Process.runSync('chmod', ['a+x', '$extractDirectory$filename'],
            workingDirectory: workingDirectoryPath);
      }
    }
  }
}

String removeFileNamePathSegment(String fullPath) =>
    fullPath.replaceRange(fullPath.lastIndexOf('/'), fullPath.length, '');

void clearTestDirectory(Directory directory) {
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
}

Future<Directory> createTempDirectoryFromDistZip(
    String distZipPath, Directory linksDirectory, String linkName) async {
  List<int> bytes = new File(distZipPath).readAsBytesSync();
  Archive archive = new ZipDecoder().decodeBytes(bytes);

  var temporaryDirectory = linksDirectory.createTempSync('$linkName-');
  await extractZipArchive(archive, temporaryDirectory.path, linkName);
  return temporaryDirectory;
}

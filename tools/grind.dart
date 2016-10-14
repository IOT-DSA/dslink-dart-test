import 'dart:async';
import 'package:grinder/grinder.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

final String etsdbLinkName = 'dslink-java-etsdb-0.16.0-SNAPSHOT';
final String etsdbRepositoryUrl =
    'https://github.com/IOT-DSA/dslink-java-etsdb';
final String javaSdkRepositoryUrl =
    'https://github.com/IOT-DSA/sdk-dslink-java';
final String historianJarName = 'historian-0.16.0-SNAPSHOT.jar';
final String dslinkJarName = 'dslink-0.16.0-SNAPSHOT.jar';
final String commonsJarName = 'commons-0.16.0-SNAPSHOT.jar';

final String projectPath = new path.Context().current;

Future<dynamic> main(List<String> args) => grind(args);

Future<Directory> cloneGitRepository(String repositoryUrl,
    [String directoryPrefix]) async {
  print('********* Cloning Git Repository $repositoryUrl ***********');
  var cloneDirectory =
      await new Directory(projectPath).createTemp(directoryPrefix);

  var process =
      await Process.run('git', ['clone', repositoryUrl, cloneDirectory.path]);

  printProcessOutput(process);

  if (process.exitCode != 0) {
    throw 'Build step failed';
  }
  return cloneDirectory;
}

void printProcessOutput(ProcessResult process) {
  print(process.stdout);
  print(process.stderr);
}

Future<Null> buildJavaLink(Directory linkDirectory) async {
  print('********* Building Java Link ***********');
  var process = await Process.run('gradle', ['clean', 'build', 'distZip'],
      workingDirectory: linkDirectory.path);

  printProcessOutput(process);
  if (process.exitCode != 0) {
    throw 'Build step failed';
  }
}

Future<Null> buildJavaSdk(Directory linkDirectory) async {
  print('********* Building Java SDK ***********');
  var process = await Process.run('gradle', ['build'],
      workingDirectory: linkDirectory.path);

  printProcessOutput(process);
  if (process.exitCode != 0) {
    throw 'Build step failed';
  }
}

Future<Directory> dumpDistZip(Directory linkDirectory, String linkName) async {
  print('********* Dumping Link DistZip ***********');
  var dumpDirectory = await new Directory(projectPath).createTemp();

  var process = await Process.run('unzip', [
    '${linkDirectory.path}/build/distributions/$linkName',
    '-d',
    dumpDirectory.path
  ]);

  printProcessOutput(process);
  if (process.exitCode != 0) {
    throw 'Build step failed';
  }

  return dumpDirectory;
}

@Task('build etsdb')
Future repackageEtsdb() async {
  print('********* Repackaging ETSDB with latest SDK ***********');
  var linkDirectory = await cloneGitRepository(etsdbRepositoryUrl, 'etsdb-');

  await buildJavaLink(linkDirectory);

  var linkDumpDirectory = await dumpDistZip(linkDirectory, etsdbLinkName);

  var sdkDirectory = await cloneGitRepository(javaSdkRepositoryUrl, 'sdk-');
  await buildJavaSdk(sdkDirectory);

  await replaceSdkJars(sdkDirectory, linkDumpDirectory);
  await zipRepackagedLink(
      linkDumpDirectory, new File('$projectPath/links/$etsdbLinkName.zip'));

  await linkDirectory.delete(recursive: true);
  await linkDumpDirectory.delete(recursive: true);
  await sdkDirectory.delete(recursive: true);
}

Future<File> zipRepackagedLink(
    Directory linkDumpDirectory, File outputFile) async {
  print('********* Zipping updated link ***********');
  var process = await Process.run('zip', ['-r', outputFile.path, etsdbLinkName],
      workingDirectory: linkDumpDirectory.path);

  printProcessOutput(process);

  if (process.exitCode != 0) {
    throw 'Build step failed';
  }
  return outputFile;
}

Future replaceSdkJars(Directory sdkDirectory, Directory linkDirectory) async {
  print('********* Replacing SDK jars in the link ***********');
  await new File(
          '${sdkDirectory.path}/sdk/historian/build/libs/sdk/$historianJarName')
      .copy('${linkDirectory.path}/$etsdbLinkName/lib/$historianJarName');
  await new File(
          '${sdkDirectory.path}/sdk/dslink/build/libs/sdk/$dslinkJarName')
      .copy('${linkDirectory.path}/$etsdbLinkName/lib/$dslinkJarName');
  await new File(
          '${sdkDirectory.path}/sdk/commons/build/libs/sdk/$commonsJarName')
      .copy('${linkDirectory.path}/$etsdbLinkName/lib/$commonsJarName');
}

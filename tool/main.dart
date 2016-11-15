import 'dart:async';
import 'package:unscripted/unscripted.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:grinder/grinder.dart';

final String sdkVersion = '0.17.0-SNAPSHOT';
final String etsdbLinkName = 'dslink-java-etsdb-$sdkVersion';
final String etsdbRepositoryUrl =
    'https://github.com/IOT-DSA/dslink-java-etsdb';
final String javaSdkRepositoryUrl =
    'https://github.com/IOT-DSA/sdk-dslink-java';
final String historianJarName = 'historian-$sdkVersion.jar';
final String dslinkJarName = 'dslink-$sdkVersion.jar';
final String commonsJarName = 'commons-$sdkVersion.jar';

final String projectPath = new path.Context().current;

Future<dynamic> main(List<String> args) => new Script(ScriptRoot).execute(args);

class ScriptRoot {
  @Command(help: 'Utility script to run tests and package links')
  ScriptRoot();

  Future<Null> buildJavaSdk(Directory linkDirectory) async {
    print('********* Building Java SDK ***********');
    final process = await Process.start('gradle', ['build'],
        workingDirectory: linkDirectory.path);

    await printProcessOutput(process);

    await process.exitCode;
  }

  Future<Directory> dumpDistZip(
      Directory linkDirectory, String linkName) async {
    print('********* Dumping Link DistZip ***********');
    final dumpDirectory = await new Directory(projectPath).createTemp('dump-');

    final process = await Process.start('unzip', [
      '${linkDirectory.path}/build/distributions/$linkName',
      '-d',
      dumpDirectory.path
    ]);

    await printProcessOutput(process);
    await process.exitCode;

    return dumpDirectory;
  }

  Future<Directory> cloneGitRepository(String repositoryUrl,
      {String branchName: 'master', String directoryPrefix: ''}) async {
    print(
        '********* Cloning Git Repository $repositoryUrl @ branch : $branchName ***********');
    final cloneDirectory =
        await new Directory(projectPath).createTemp(directoryPrefix);

    final process = await Process.start(
        'git', ['clone', '-b', branchName, repositoryUrl, cloneDirectory.path]);

    await printProcessOutput(process);

    return cloneDirectory;
  }

  Future<Null> printProcessOutput(Process p) async {
    p.stderr.listen((List<int> out) => print(new Utf8Decoder().convert(out)));
    p.stdout.listen((List<int> out) => print(new Utf8Decoder().convert(out)));

    if (await p.exitCode != 0) {
      throw 'Build step failed';
    }
  }

  Future<Null> buildJavaLink(Directory linkDirectory) async {
    print('********* Building Java Link ***********');
    final process = await Process.start('gradle', ['clean', 'build', 'distZip'],
        workingDirectory: linkDirectory.path);

    await printProcessOutput(process);

    await process.exitCode;
  }

  @SubCommand(
      help: 'Run integrated tests on every tested DSLinks with a '
          'specific version of the Java SDK.')
  Future<Null> runTestsForSdkPullRequest(
      {@Option(
          help: 'If specified, the script will not clone the Java SDK but '
              'rather use an already checked out version.')
          String pathToSdk}) async {
    if (pathToSdk == null) {
      final branchName = getBranchName();

      await repackageEtsdb(sdkBranchName: branchName);
    } else {}

    new PubApp.local('test').run([]);
  }

  @SubCommand(
      help: 'Repackage dslink-java-etsdb with a given version of the Java SDK. '
          'To do so, it will clone the GitHub repository.')
  Future<Null> repackageEtsdb(
      {@Option(help: 'Branch of the Java SDK (available on GitHub)')
          String sdkBranchName: 'master'}) async {
    print('********* Repackaging ETSDB ***********');
    final linkDirectory =
        await cloneGitRepository(etsdbRepositoryUrl, directoryPrefix: 'etsdb-');

    await buildJavaLink(linkDirectory);

    final linkDumpDirectory = await dumpDistZip(linkDirectory, etsdbLinkName);

    final sdkDirectory = await cloneGitRepository(javaSdkRepositoryUrl,
        directoryPrefix: 'sdk-', branchName: sdkBranchName);
    await buildJavaSdk(sdkDirectory);

    await replaceSdkJars(sdkDirectory, linkDumpDirectory);
    await zipRepackagedLink(
        linkDumpDirectory, new File('$projectPath/links/$etsdbLinkName.zip'));

    await linkDirectory.delete(recursive: true);
    await linkDumpDirectory.delete(recursive: true);
    await sdkDirectory.delete(recursive: true);
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

  Future<File> zipRepackagedLink(
      Directory linkDumpDirectory, File outputFile) async {
    print('********* Zipping updated link ***********');
    final process = await Process.start(
        'zip', ['-r', outputFile.path, etsdbLinkName],
        workingDirectory: linkDumpDirectory.path);

    await printProcessOutput(process);

    if (await process.exitCode != 0) {
      throw 'Build step failed';
    }
    return outputFile;
  }

  String getBranchName() {
    final branchName = Platform.environment['BRANCH_NAME']
        ?.replaceAll('/refs/heads/', '')
        ?.replaceAll('ref/heads/', '');
    if (branchName == null || branchName.isEmpty) {
      return 'master';
    }

    return branchName;
  }
}

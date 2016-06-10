## Overview
This project is meant to contain all the end-to-end tests for DSLinks we develop.

## Continuous Integration
Right now, this project gives daily status about the tested links against the latest version of the SDK and the latest version
of Dart Broker. No build integration is prevented by the result of these tests.

If you have the required access, you can see the results [here](https://ci.dev.dglogik.com/viewType.html?buildTypeId=Dsa_DSLinksTests).

## How to write new tests
The tests are organized in the `test/` directory. Each tested DSLink contains its own `dslinkName_test.dart` file. The `base_test.dart`
file covers general tests for the SDK and the test framework itself.

If your link is written in Dart, you can either add its dependency to `pubspec.yaml` and launch/stop it programmatically, or you can also
provide a distZip and let the framework launch/stop it. You can take example from `etsdb_test.dart` which is the first link to be tested.

If you provide a distZip, add it to the `links/` directory, and use the functions provided in the library `dslink_test_framework.dart`
to load the start the links.

The tests are written using the official [test framework in Dart](https://github.com/dart-lang/test). You can check their README out, it
contains a lot of useful information.

## FAQ
Q: What Broker does it use?

A: You can write the tests to use a local broker, or there is also functions in the `dslink_test_framework.dart` library to start an
in-memory broker that'll be cleaned between each test, if you start/kill it in-between the tests.

Q: Can I test Java link (or any link written in another language)

A: Yes, you just have to write the test against a distZip. Right now there's no way to automatically fetch the latest version of a distZip.
The only downside of this, is that you will have to manage the timings of launching/killing the link manually. Some links take more time
than others to kickoff, so some tweaking is necessary on your end.

Q: Can I put break points in a link to debug a test?

A: If the link you test is running from a distZip, No.

If you're running a link manually in the IDE, yes. In fact, you can pretty easily
launch a link manually from another run configuration and put break points in there. You'll end up with 2 projects running, but with
the possibility to debug the link.

Q: Can I put break points in the test code?

A: IntelliJ has some problems with its integration with the Dart test framework. To accomplish that, you have to manually create a run
configuration, and select the type `Dart command line app`, select the test file you want to debug, and run it as `Debug`.


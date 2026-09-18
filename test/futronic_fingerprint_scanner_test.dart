import 'package:flutter_test/flutter_test.dart';
import 'package:futronic_fingerprint_scanner/futronic_fingerprint_scanner.dart';
import 'package:futronic_fingerprint_scanner/futronic_fingerprint_scanner_platform_interface.dart';
import 'package:futronic_fingerprint_scanner/futronic_fingerprint_scanner_method_channel.dart';

void main() {
  final FutronicFingerprintScannerPlatform initialPlatform =
      FutronicFingerprintScannerPlatform.instance;

  test('$MethodChannelFutronicFingerprintScanner is the default instance', () {
    expect(initialPlatform,
        isInstanceOf<MethodChannelFutronicFingerprintScanner>());
  });

  test('getPlatformVersion', () async {
    FutronicFingerprintScanner futronicFingerprintScannerPlugin =
        FutronicFingerprintScanner();
    //MockFutronicFingerprintScannerPlatform fakePlatform = MockFutronicFingerprintScannerPlatform();
    //FutronicFingerprintScannerPlatform.instance = fakePlatform;

    /*  expect(await futronicFingerprintScannerPlugin.getPlatformVersion(), '42');*/
  });
}

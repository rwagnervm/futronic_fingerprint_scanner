import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:futronic_fingerprint_scanner/fingerprint_widget.dart';
import 'package:futronic_fingerprint_scanner/futronic_fingerprint_scanner.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String message = 'Unknown';
  bool invertChecked = false;
  bool nfiqChecked = false;
  bool lfdChecked = false;
  bool isScanning = false;
  Size scannerSize = const Size(9, 13);
  final _futronicFingerprintScannerPlugin = FutronicFingerprintScanner();

  @override
  void initState() {
    super.initState();
    initFingerprint();
  }

  Future<void> initFingerprint() async {
    _futronicFingerprintScannerPlugin.onMessage = (message) {
      print(message);
      setState(() {
        this.message = message;
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            Wrap(
              children: [
                TextButton(
                    onPressed: isScanning
                        ? null
                        : () async {
                            isScanning =
                                (await _futronicFingerprintScannerPlugin.methods
                                        .scan()) ??
                                    false;
                            if (isScanning) {
                              await Future.delayed(const Duration(seconds: 1));
                              scannerSize =
                                  await _futronicFingerprintScannerPlugin
                                          .methods
                                          .getScannerSize() ??
                                      const Size(9, 13);
                              if (scannerSize == Size.zero) {
                                scannerSize = const Size(9, 13);
                              }
                              print('scannerSize: $scannerSize');
                            }
                            setState(() {});
                          },
                    child: const Text('Start Scan')),
                TextButton(
                    onPressed: isScanning
                        ? () async {
                            isScanning =
                                !((await _futronicFingerprintScannerPlugin
                                        .methods
                                        .stop()) ??
                                    false);
                            setState(() {});
                          }
                        : null,
                    child: const Text('Stop')),
                TextButton(
                    onPressed: isScanning
                        ? () {
                            invertChecked = !invertChecked;
                            _futronicFingerprintScannerPlugin.methods
                                .setCheckInvert(invertChecked);
                            setState(() {});
                          }
                        : null,
                    child: Text('Invert ($invertChecked)')),
                TextButton(
                    onPressed: isScanning
                        ? () {
                            nfiqChecked = !nfiqChecked;
                            _futronicFingerprintScannerPlugin.methods
                                .setCheckNFIQ(nfiqChecked);
                            setState(() {});
                          }
                        : null,
                    child: Text('NFIQ ($nfiqChecked)')),
                TextButton(
                    onPressed: isScanning
                        ? () {
                            lfdChecked = !lfdChecked;
                            _futronicFingerprintScannerPlugin.methods
                                .setCheckLFD(lfdChecked);
                            setState(() {});
                          }
                        : null,
                    child: Text('LFD ($lfdChecked)')),
              ],
            ),
            Expanded(
              child: RepaintBoundary(
                child: AspectRatio(
                  aspectRatio: scannerSize.aspectRatio,
                  child: const FingerPrintWidget(),
                ),
              ),
            ),
            Text(message),
            TextButton(
                onPressed: isScanning
                    ? () async {
                        Directory appDocDir =
                            await getApplicationDocumentsDirectory();
                        String appDocPath = appDocDir.path;
                        const fileFormat = FileFormat.bitmap;
                        final fileName = 'test${fileFormat.extension}';
                        print(appDocPath);
                        _futronicFingerprintScannerPlugin.methods
                            .saveImage(fileFormat, appDocPath, '/$fileName');
                        setState(() {});
                      }
                    : null,
                child: const Text('Save')),
            TextButton(
                onPressed: isScanning
                    ? () async {
                        _futronicFingerprintScannerPlugin.methods
                            .getFingerprintImageBytes()
                            .then((value) {
                          if (value != null) {
                            print(value);
                          }
                        });
                        setState(() {});
                      }
                    : null,
                child: const Text('get bytes')),
          ],
        ),
      ),
    );
  }
}

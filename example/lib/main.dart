import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:futronic_fingerprint_scanner/fingerprint_widget.dart';
import 'package:futronic_fingerprint_scanner/futronic_fingerprint_scanner.dart';
import 'package:http/http.dart' as http;
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
  String message = 'Iniciando captura...';
  bool invertChecked = true;
  bool nfiqChecked = true;
  bool lfdChecked = false;
  bool isScanning = false;
  Size scannerSize = const Size(9, 13);
  final _futronicFingerprintScannerPlugin = FutronicFingerprintScanner();

  bool _isValidating = false;
  bool _hasValidated = false;
  String _validationStatus = 'Aguardando digital com NFIQ = 1...';
  String _validationResponseBody = '';
  int? _validationStatusCode;

  @override
  void initState() {
    super.initState();
    initFingerprint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCaptureAuto();
    });
  }

  Future<void> initFingerprint() async {
    _futronicFingerprintScannerPlugin.onMessage = (msg) {
      if (!mounted) return;
      setState(() {
        message = msg;
      });

      // Verifica se a mensagem contém o cálculo de NFIQ=1
      final match = RegExp(r'NFIQ=(\d+)').firstMatch(msg);
      if (match != null && match.group(1) == '1') {
        if (!_isValidating && !_hasValidated) {
          _onNFIQ1Detected();
        }
      }
    };
  }

  Future<void> _startCaptureAuto() async {
    // 1. Habilitar Invert e NFIQ
    await _futronicFingerprintScannerPlugin.methods.setCheckInvert(true);
    await _futronicFingerprintScannerPlugin.methods.setCheckNFIQ(true);
    invertChecked = true;
    nfiqChecked = true;

    // 2. Iniciar escaneamento
    final started =
        await _futronicFingerprintScannerPlugin.methods.scan() ?? false;
    isScanning = started;

    if (isScanning) {
      await Future.delayed(const Duration(seconds: 1));
      scannerSize =
          await _futronicFingerprintScannerPlugin.methods.getScannerSize() ??
              const Size(9, 13);
      if (scannerSize == Size.zero) {
        scannerSize = const Size(9, 13);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _onNFIQ1Detected() async {
    _isValidating = true;
    if (mounted) {
      setState(() {
        _validationStatus = 'NFIQ = 1 detectado! Obtendo imagem WSQ...';
      });
    }

    try {
      // 1. Obter os bytes do WSQ (direto da memória ou via saveImage de fallback)
      Uint8List? wsqBytes =
          await _futronicFingerprintScannerPlugin.methods.getWSQBytes();

      if (wsqBytes == null || wsqBytes.isEmpty) {
        final tempDir = await getTemporaryDirectory();
        const fileName = '/auto_nfiq1_fingerprint.wsq';
        await _futronicFingerprintScannerPlugin.methods
            .saveImage(FileFormat.wsq, tempDir.path, fileName);
        final file = File('${tempDir.path}$fileName');
        if (await file.exists()) {
          wsqBytes = await file.readAsBytes();
        }
      }

      if (wsqBytes == null || wsqBytes.isEmpty) {
        if (mounted) {
          setState(() {
            _validationStatus = 'Erro: Não foi possível obter os dados WSQ.';
            _isValidating = false;
          });
        }
        return;
      }

      final wsqBase64 = base64Encode(wsqBytes);

      // Parar o scan para congelar o frame validado
      await _futronicFingerprintScannerPlugin.methods.stop();
      isScanning = false;

      if (mounted) {
        setState(() {
          _validationStatus =
              'WSQ gerado (${wsqBytes!.length} bytes). Enviando para Datavalid...';
        });
      }

      // 2. Preparar payload com os 10 dedos
      const fingerPositions = [
        "POLEGAR_DIREITO",
        "INDICADOR_DIREITO",
        "MEDIO_DIREITO",
        "ANELAR_DIREITO",
        "MINIMO_DIREITO",
        "POLEGAR_ESQUERDO",
        "INDICADOR_ESQUERDO",
        "MEDIO_ESQUERDO",
        "ANELAR_ESQUERDO",
        "MINIMO_ESQUERDO",
      ];

      final biometriaDigital = fingerPositions
          .map((pos) => {
                "essencial": false,
                "posicao": pos,
                "formato": "WSQ",
                "base64": wsqBase64,
              })
          .toList();

      final payload = {
        "privacidade": {
          "rfb": {"id_template": "6a0b47bcc4af527c3b13681d"},
          "senatran": {
            "token":
                "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0ZW1wbGF0ZUlkIjoiMDEyMDI2LTAwMDAxIiwiaXNDb25zZW50aW1lbnRvIjpmYWxzZSwiaWRDb25zZW50aW1lbnRvIjpudWxsLCJjbnBqVXN1YXJpbyI6IjMzNjgzMTExMDAwMTA3IiwiY25wakFudWVudGUiOiIzNzExNTM0MjAwNDE1NCIsImNucGpHY2MiOiIzMzY4MzExMTAwMDEwNyIsImRhdGFDcmlhY2FvIjoiMjAyNi0wMS0wMVQwMDowMDowMCIsImRhdGFFeHBpcmFjYW8iOiIyMDUwLTEyLTMxVDIzOjU5OjU5In0.demo",
            "cnpj_anuente": "37115342004154",
          },
        },
        "cpf": "87333953300",
        "validacao": {
          "biometria_digital": biometriaDigital,
        },
      };

      // 3. Chamada HTTP para Datavalid
      final validationResponse = await http.post(
        Uri.parse(
          'https://gateway.apiserpro.serpro.gov.br/datavalid-demonstracao/v5/pessoa-fisica/validacao',
        ),
        headers: {
          'accept': 'application/json',
          'Authorization': 'Bearer 06aef429-a981-3ec5-a1f8-71d38d86481e',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      _hasValidated = true;
      _isValidating = false;
      _validationStatusCode = validationResponse.statusCode;
      _validationResponseBody = validationResponse.body;

      String statusMsg = 'Validação concluída (Status ${validationResponse.statusCode})';

      if (validationResponse.statusCode == 200) {
        try {
          final data = jsonDecode(validationResponse.body);
          final validacao = data['validacao'];
          if (validacao != null && validacao['biometria_digital'] != null) {
            final bioDigital = validacao['biometria_digital'] as List;
            final matchFingers = bioDigital.where((item) {
              final sim = item['similaridade'];
              if (sim is num) return sim > 0.85;
              if (sim is String) return (double.tryParse(sim) ?? 0.0) > 0.85;
              return false;
            }).toList();

            if (matchFingers.isNotEmpty) {
              final dedos = matchFingers.map((e) => '${e['posicao']} (${e['similaridade']})').join(', ');
              statusMsg = '✓ Match encontrado: $dedos';
            } else {
              statusMsg = '✗ Nenhum dedo com similaridade > 0.85';
            }
          }
        } catch (e) {
          debugPrint('Erro ao parsear JSON de resposta: $e');
        }
      }

      if (mounted) {
        setState(() {
          _validationStatus = statusMsg;
        });
      }
    } catch (e) {
      _isValidating = false;
      if (mounted) {
        setState(() {
          _validationStatus = 'Erro na requisição: $e';
        });
      }
    }
  }

  void _resetValidationAndRestart() async {
    _hasValidated = false;
    _isValidating = false;
    _validationResponseBody = '';
    _validationStatusCode = null;
    _validationStatus = 'Aguardando digital com NFIQ = 1...';
    await _startCaptureAuto();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Futronic Scanner - Datavalid Demo'),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barra de Status do Datavalid
                Card(
                  color: _hasValidated
                      ? (_validationStatusCode == 200
                          ? Colors.green.shade50
                          : Colors.orange.shade50)
                      : (_isValidating ? Colors.blue.shade50 : Colors.grey.shade100),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_isValidating)
                              const Padding(
                                padding: EdgeInsets.only(right: 8.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            else if (_hasValidated)
                              Icon(
                                _validationStatusCode == 200
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color: _validationStatusCode == 200
                                    ? Colors.green
                                    : Colors.orange,
                                size: 20,
                              ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _validationStatus,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_validationResponseBody.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Resposta da API:',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(0, 0, 0, 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              child: Text(
                                _validationResponseBody,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Controles Manuais
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isScanning
                          ? null
                          : () async {
                              _hasValidated = false;
                              await _startCaptureAuto();
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Scan'),
                    ),
                    ElevatedButton.icon(
                      onPressed: isScanning
                          ? () async {
                              isScanning = !((await _futronicFingerprintScannerPlugin
                                      .methods
                                      .stop()) ??
                                  false);
                              setState(() {});
                            }
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _resetValidationAndRestart,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Revalidar'),
                    ),
                  ],
                ),

                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilterChip(
                      label: Text('Invert ($invertChecked)'),
                      selected: invertChecked,
                      onSelected: isScanning
                          ? (val) {
                              invertChecked = val;
                              _futronicFingerprintScannerPlugin.methods
                                  .setCheckInvert(invertChecked);
                              setState(() {});
                            }
                          : null,
                    ),
                    FilterChip(
                      label: Text('NFIQ ($nfiqChecked)'),
                      selected: nfiqChecked,
                      onSelected: isScanning
                          ? (val) {
                              nfiqChecked = val;
                              _futronicFingerprintScannerPlugin.methods
                                  .setCheckNFIQ(nfiqChecked);
                              setState(() {});
                            }
                          : null,
                    ),
                    FilterChip(
                      label: Text('LFD ($lfdChecked)'),
                      selected: lfdChecked,
                      onSelected: isScanning
                          ? (val) {
                              lfdChecked = val;
                              _futronicFingerprintScannerPlugin.methods
                                  .setCheckLFD(lfdChecked);
                              setState(() {});
                            }
                          : null,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Visualizador da Digital
                Center(
                  child: Container(
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RepaintBoundary(
                      child: AspectRatio(
                        aspectRatio: scannerSize.aspectRatio,
                        child: const FingerPrintWidget(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),

                const SizedBox(height: 8),

                // Ações de Salvar e Obter Bytes
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        final appDocDir =
                            await getApplicationDocumentsDirectory();
                        const fileFormat = FileFormat.bitmap;
                        final fileName = 'test${fileFormat.extension}';
                        await _futronicFingerprintScannerPlugin.methods
                            .saveImage(
                                fileFormat, appDocDir.path, '/$fileName');
                        setState(() {});
                      },
                      child: const Text('Salvar BMP'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final appDocDir =
                            await getApplicationDocumentsDirectory();
                        const fileFormat = FileFormat.wsq;
                        final fileName = 'test${fileFormat.extension}';
                        await _futronicFingerprintScannerPlugin.methods
                            .saveImage(
                                fileFormat, appDocDir.path, '/$fileName');
                        setState(() {});
                      },
                      child: const Text('Salvar WSQ'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

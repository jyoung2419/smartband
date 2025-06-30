import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class SmartWatchScreen extends StatefulWidget {
  const SmartWatchScreen({super.key});

  @override
  State<SmartWatchScreen> createState() => _SmartWatchScreenState();
}

class _SmartWatchScreenState extends State<SmartWatchScreen> {
  final flutterReactiveBle = FlutterReactiveBle();
  final List<DiscoveredDevice> h60Devices = [];
  DiscoveredDevice? targetDevice;
  bool isConnected = false;
  StreamSubscription<DiscoveredDevice>? scanStream;
  StreamSubscription<List<int>>? notifySub;

  String? sys, dia, hr, temp, temp2;

  final h60ServiceUuid = Uuid.parse("0000FEE7-0000-1000-8000-00805F9B34FB");
  final h60CharFEA1 = Uuid.parse("0000FEA1-0000-1000-8000-00805F9B34FB");

  @override
  void initState() {
    super.initState();
    debugPrint("📦 initState 호출됨");
    _initBLE();
  }

  Future<void> _initBLE() async {
    if (await _requestPermissions()) _scanDevices();
  }

  Future<bool> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ];

    for (final p in permissions) {
      final status = await p.status;
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      if (status.isDenied && !(await p.request()).isGranted) return false;
    }

    return true;
  }

  void _scanDevices() {
    scanStream = flutterReactiveBle.scanForDevices(withServices: []).listen((device) {
      if (device.name.contains("H60") &&
          !h60Devices.any((d) => d.id == device.id)) {
        setState(() => h60Devices.add(device));
        debugPrint("✅ H60 후보 기기 발견: ${device.name}");
      }
    });
  }

  void _connectToDevice(DiscoveredDevice device) {
    flutterReactiveBle.connectToDevice(id: device.id).listen(
          (state) async {
        if (state.connectionState == DeviceConnectionState.connected) {
          scanStream?.cancel();
          setState(() {
            targetDevice = device;
            isConnected = true;
          });

          final services = await flutterReactiveBle.discoverServices(device.id);
          final hasFEA1 = services.any((s) =>
              s.characteristics.any((c) => c.characteristicId == h60CharFEA1));

          if (!hasFEA1) {
            debugPrint("❌ FEA1 캐릭터리스틱 발견되지 않음");
            return;
          }

          final fea1Char = QualifiedCharacteristic(
            serviceId: h60ServiceUuid,
            characteristicId: h60CharFEA1,
            deviceId: device.id,
          );

          notifySub?.cancel();
          notifySub = flutterReactiveBle.subscribeToCharacteristic(fea1Char).listen(
                (data) {
              debugPrint("📡 Notify 수신: $data");
              debugPrint("📡 Notify 수신 (HEX): ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}");

              if (data.length >= 6) {
                setState(() {
                  sys = data[1].toString();
                  dia = data[2].toString();
                  hr = data[3].toString();
                  temp = data[4].toString();
                  temp2 = data[5].toString();
                });
              }
            },
            onError: (e) => debugPrint("❌ Notify 수신 실패: $e"),
          );

          debugPrint("✅ 연결 및 notify 구독 완료");
        }
      },
      onError: (e) => debugPrint("❌ 연결 실패: $e"),
    );
  }

  @override
  void dispose() {
    scanStream?.cancel();
    notifySub?.cancel();
    notifySub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: AppBar(
            title: const Text(
              "Smart Watch 측정",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.white,
              statusBarIconBrightness: Brightness.dark,
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("🔍 스캔된 기기 목록", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: h60Devices.length,
                itemBuilder: (context, index) {
                  final device = h60Devices[index];
                  return ListTile(
                      title: Text(
                        device.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        device.id,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                      trailing: isConnected && device.id == targetDevice?.id
                        ? const Text(
                        "✅ 연결됨",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                        :ElevatedButton(
                      onPressed: () => _connectToDevice(device),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.lightGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text("연결"),
                    )
                  );
                },
              ),
            ),
            const Divider(),
            Text(
              "연결 상태: ${isConnected ? "✅ 연결됨" : "❌ 미연결"}",
              style: TextStyle(
                color: isConnected ? Colors.green : Colors.red,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (isConnected && sys != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("🫀 수축기 혈압 (SYS): $sys mmHg"),
                  Text("🫀 이완기 혈압 (DIA): $dia mmHg"),
                  Text("💓 심박수 (HR): $hr bpm"),
                  Text("🌡️ 체온 (TEMP): $temp °C"),
                  Text("🌡️ 체온 (TEMP2): $temp2 °C"),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

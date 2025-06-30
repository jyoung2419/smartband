import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

final ble = FlutterReactiveBle();

final hrServiceUuid = Uuid.parse("0000180D-0000-1000-8000-00805f9b34fb");
final hrCharUuid = Uuid.parse("00002A37-0000-1000-8000-00805f9b34fb");

class PolarScreen extends StatefulWidget {
  const PolarScreen({super.key});

  @override
  State<PolarScreen> createState() => _PolarScreenState();
}

class _PolarScreenState extends State<PolarScreen> {
  String? _hr;
  String? _deviceName;
  List<DiscoveredDevice> _foundDevices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _foundDevices.clear();
      _isScanning = true;
    });

    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();

    ble.scanForDevices(withServices: [hrServiceUuid]).listen((device) {
      if (!_foundDevices.any((d) => d.id == device.id)) {
        setState(() {
          _foundDevices.add(device);
        });
      }
    }).onDone(() {
      setState(() {
        _isScanning = false;
      });
    });
  }

  void _connectAndListen(DiscoveredDevice device) {
    setState(() {
      _isConnecting = true;
      _deviceName = device.name;
      _hr = null;
    });

    final char = QualifiedCharacteristic(
      deviceId: device.id,
      serviceId: hrServiceUuid,
      characteristicId: hrCharUuid,
    );

    _connectionSub = ble.connectToDevice(id: device.id).listen((_) {});

    _dataSub = ble.subscribeToCharacteristic(char).listen((data) {
      if (data.isNotEmpty) {
        final bpm = data[1];
        setState(() {
          _hr = bpm.toString();
        });
      }
    });
  }

  void _disconnect() {
    _dataSub?.cancel();
    _connectionSub?.cancel();
    setState(() {
      _isConnecting = false;
      _deviceName = null;
      _hr = null;
    });
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
              "Polar SmartBand 심박수",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
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
      body: _isConnecting
          ? _buildMeasurementView()
          : _buildDeviceListView(),
    );
  }

  Widget _buildDeviceListView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("스캔된 기기 목록", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: _foundDevices.isEmpty
                ? const Center(child: Text("디바이스를 검색 중입니다..."))
                : ListView.builder(
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              itemCount: _foundDevices.length,
              itemBuilder: (context, index) {
                final device = _foundDevices[index];
                return Card(
                  color: Colors.white,
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    title: Text(
                      device.name.isNotEmpty ? device.name : "(이름 없음)",
                      style: const TextStyle(fontSize: 18),
                    ),
                    subtitle: Text(
                      device.id,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    trailing: ElevatedButton(
                      onPressed: () => _connectAndListen(device),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("연결"),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMeasurementView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_deviceName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "Device: $_deviceName",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                ),
              ),
            ),
          const Icon(Icons.favorite, size: 80, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            _hr != null ? "$_hr bpm" : "측정 중...",
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (_hr == null)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: SpinKitPulse(color: Colors.red, size: 50),
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _disconnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("연결 해제", style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

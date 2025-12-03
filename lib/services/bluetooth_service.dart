import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';
import '../utils/device_id_encoder.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  bool _isInitialized = false;
  bool _isAdvertising = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  bool get isAdvertising => _isAdvertising;

  // ==================== INITIALIZATION ====================

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await BlePeripheral.initialize();
      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize BLE peripheral: $e');
    }
  }

  Future<bool> isPeripheralSupported() async {
    try {
      final result = await BlePeripheral.isSupported();
      return result == true;
    } catch (e) {
      return false;
    }
  }

  // ==================== ADVERTISING (Faculty) ====================

  /// Start advertising with session token
  Future<void> startAdvertising(String sessionToken) async {
    if (_isAdvertising) return;

    final localName = '${AppConstants.bleDevicePrefix}$sessionToken';

    try {
      // Add service
      await BlePeripheral.addService(
        BleService(
          uuid: AppConstants.bleServiceUuid,
          primary: true,
          characteristics: [],
        ),
      );

      // Start advertising
      await BlePeripheral.startAdvertising(
        services: [AppConstants.bleServiceUuid],
        localName: localName,
      );

      // Verify advertising started
      await Future.delayed(const Duration(milliseconds: 500));
      _isAdvertising = await BlePeripheral.isAdvertising() ?? false;

      if (!_isAdvertising) {
        // Retry without service UUID
        await BlePeripheral.startAdvertising(
          services: [],
          localName: localName,
        );
        _isAdvertising = true;
      }
    } catch (e) {
      _isAdvertising = false;
      throw Exception('Failed to start advertising: $e');
    }
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    try {
      await BlePeripheral.stopAdvertising();
      _isAdvertising = false;
    } catch (e) {
      throw Exception('Failed to stop advertising: $e');
    }
  }

  // ==================== SCANNING (Student) ====================

  /// Check if Bluetooth is enabled
  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Check if Location Services (GPS) is enabled - REQUIRED for BLE scanning on Android
  Future<bool> isLocationServiceEnabled() async {
    if (Platform.isAndroid) {
      return await Permission.location.serviceStatus.isEnabled;
    }
    return true; // iOS doesn't require this check
  }

  /// Turn on Bluetooth adapter
  Future<void> turnOnBluetooth() async {
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
  }

  /// Listen to Bluetooth adapter state
  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  /// Pre-scan checks - returns error message if checks fail, null if OK
  Future<String?> preScanChecks() async {
    // Check Bluetooth is ON
    final btOn = await isBluetoothOn();
    if (!btOn) {
      return 'Please turn on Bluetooth';
    }

    // Check Location Services (GPS) - CRITICAL for OnePlus, Nothing, Xiaomi, etc.
    if (Platform.isAndroid) {
      final locationEnabled = await isLocationServiceEnabled();
      if (!locationEnabled) {
        return 'Please enable Location Services (GPS) for Bluetooth scanning';
      }
    }

    // Check permissions
    final btScan = await Permission.bluetoothScan.status;
    final btConnect = await Permission.bluetoothConnect.status;
    final location = await Permission.location.status;

    if (!btScan.isGranted || !btConnect.isGranted) {
      return 'Bluetooth permissions are required';
    }

    if (Platform.isAndroid && !location.isGranted) {
      return 'Location permission is required for Bluetooth scanning';
    }

    return null; // All checks passed
  }

  /// Start scanning for BLE devices with optimized settings for all devices
  /// Returns a stream of scan results
  Stream<List<ScanResult>> startScanning({
    Duration timeout = const Duration(seconds: 30),
  }) {
    // Use specific settings for better compatibility with OnePlus, Nothing, etc.
    FlutterBluePlus.startScan(
      timeout: timeout,
      // Scan in low latency mode for faster discovery
      androidScanMode: AndroidScanMode.lowLatency,
      // Allow duplicates to get continuous RSSI updates
      continuousUpdates: true,
      // Don't filter by services - scan all devices
      withServices: [],
      // Remove any name filters
      withNames: [],
    );
    return FlutterBluePlus.scanResults;
  }

  /// Start aggressive scanning for problematic devices (OnePlus, Nothing, Xiaomi)
  Future<Stream<List<ScanResult>>> startAggressiveScanning({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Stop any existing scan first
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 500));

    // Use balanced mode with longer scan window
    FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.balanced,
      continuousUpdates: true,
      continuousDivisor: 1, // Report every result
    );
    
    return FlutterBluePlus.scanResults;
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  /// Find attendance session beacon from scan results
  /// Returns session token if found
  String? findSessionBeacon(List<ScanResult> results) {
    for (var result in results) {
      // Check platform name
      final platformName = result.device.platformName;
      if (platformName.startsWith(AppConstants.bleDevicePrefix)) {
        return DeviceIdEncoder.extractSessionToken(
          platformName,
          AppConstants.bleDevicePrefix,
        );
      }

      // Check advertisement name
      final advName = result.advertisementData.advName;
      if (advName.startsWith(AppConstants.bleDevicePrefix)) {
        return DeviceIdEncoder.extractSessionToken(
          advName,
          AppConstants.bleDevicePrefix,
        );
      }

      // Check service UUID
      final hasService = result.advertisementData.serviceUuids.any(
        (uuid) => uuid.toString().toLowerCase() == AppConstants.bleServiceUuid,
      );
      if (hasService) {
        // Try to extract from manufacturer data
        final mfgData = result.advertisementData.manufacturerData;
        final data = mfgData[AppConstants.bleManufacturerId] ??
            mfgData[0xFFFF];
        if (data != null) {
          return DeviceIdEncoder.decodeManufacturerData(data);
        }
      }
    }
    return null;
  }

  /// Scan for a specific session device ID
  Future<ScanResult?> findDeviceById(
    String deviceId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final completer = Completer<ScanResult?>();

    FlutterBluePlus.startScan(timeout: timeout);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        final platformName = result.device.platformName;
        final advName = result.advertisementData.advName;

        if (platformName.contains(deviceId) || advName.contains(deviceId)) {
          if (!completer.isCompleted) {
            completer.complete(result);
            stopScanning();
          }
          return;
        }
      }
    });

    // Handle timeout
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
        stopScanning();
      }
    });

    return completer.future;
  }

  /// Dispose resources
  void dispose() {
    stopScanning();
    if (_isAdvertising) {
      stopAdvertising();
    }
  }
}

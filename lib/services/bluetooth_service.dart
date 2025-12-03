import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';
import '../utils/device_id_encoder.dart';

/// Multi-strategy Bluetooth Service for maximum device compatibility
/// Implements parallel scanning/advertising techniques for Android devices
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  bool _isInitialized = false;
  bool _isAdvertising = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  
  // Multi-scan state
  Timer? _scanCycleTimer;
  Timer? _advertisingRefreshTimer;
  int _currentScanMode = 0;
  final StreamController<List<ScanResult>> _mergedResultsController = 
      StreamController<List<ScanResult>>.broadcast();
  final Map<String, ScanResult> _discoveredDevices = {};

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
  // Multi-strategy advertising for maximum device compatibility

  String? _currentSessionToken;

  /// Start multi-strategy advertising with session token
  /// Tries multiple advertising configurations for maximum compatibility
  Future<void> startAdvertising(String sessionToken) async {
    if (_isAdvertising) return;

    _currentSessionToken = sessionToken;
    final localName = '${AppConstants.bleDevicePrefix}$sessionToken';

    try {
      // Strategy 1: Full advertising with service UUID and local name
      bool success = await _tryAdvertisingStrategy1(localName);
      
      // Strategy 2: Advertising with just local name (no service UUID)
      if (!success) {
        success = await _tryAdvertisingStrategy2(localName);
      }
      
      // Strategy 3: Advertising with manufacturer data
      if (!success) {
        success = await _tryAdvertisingStrategy3(sessionToken, localName);
      }

      if (!success) {
        throw Exception('All advertising strategies failed');
      }

      _isAdvertising = true;
      
      // Start periodic advertising refresh for better visibility
      _startAdvertisingRefresh(localName);
      
    } catch (e) {
      _isAdvertising = false;
      throw Exception('Failed to start advertising: $e');
    }
  }

  /// Strategy 1: Full BLE advertising with service UUID
  Future<bool> _tryAdvertisingStrategy1(String localName) async {
    try {
      await BlePeripheral.addService(
        BleService(
          uuid: AppConstants.bleServiceUuid,
          primary: true,
          characteristics: [],
        ),
      );

      await BlePeripheral.startAdvertising(
        services: [AppConstants.bleServiceUuid],
        localName: localName,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      return await BlePeripheral.isAdvertising() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Strategy 2: Advertising with local name only (no service UUID)
  Future<bool> _tryAdvertisingStrategy2(String localName) async {
    try {
      await BlePeripheral.stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 200));
      
      await BlePeripheral.startAdvertising(
        services: [],
        localName: localName,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      return await BlePeripheral.isAdvertising() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Strategy 3: Advertising with manufacturer data
  Future<bool> _tryAdvertisingStrategy3(String token, String localName) async {
    try {
      await BlePeripheral.stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Encode token into manufacturer data
      final mfgData = _encodeManufacturerData(token);
      
      await BlePeripheral.startAdvertising(
        services: [],
        localName: localName,
        manufacturerData: ManufacturerData(
          manufacturerId: AppConstants.bleManufacturerId,
          data: mfgData,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      return await BlePeripheral.isAdvertising() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Encode session token into manufacturer data bytes
  Uint8List _encodeManufacturerData(String token) {
    final bytes = token.codeUnits;
    return Uint8List.fromList(bytes.take(20).toList()); // Max 20 bytes
  }

  /// Periodic advertising refresh to maintain visibility on all devices
  void _startAdvertisingRefresh(String localName) {
    _advertisingRefreshTimer?.cancel();
    
    // Refresh advertising every 30 seconds to maintain visibility
    _advertisingRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        if (_isAdvertising && _currentSessionToken != null) {
          try {
            await BlePeripheral.stopAdvertising();
            await Future.delayed(const Duration(milliseconds: 300));
            await BlePeripheral.startAdvertising(
              services: [AppConstants.bleServiceUuid],
              localName: localName,
            );
          } catch (e) {
            // Ignore refresh errors
          }
        }
      },
    );
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    _advertisingRefreshTimer?.cancel();
    _advertisingRefreshTimer = null;
    _currentSessionToken = null;

    if (!_isAdvertising) return;

    try {
      await BlePeripheral.stopAdvertising();
      _isAdvertising = false;
    } catch (e) {
      _isAdvertising = false;
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

  /// Start MULTI-STRATEGY aggressive scanning for all Android devices
  /// Cycles through different scan modes for maximum compatibility
  /// Works on OnePlus, Nothing, Xiaomi, Samsung, Pixel, etc.
  Future<Stream<List<ScanResult>>> startAggressiveScanning({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Clear previous results
    _discoveredDevices.clear();
    _currentScanMode = 0;
    
    // Stop any existing scan first
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 300));

    // Start the first scan mode
    await _startScanWithMode(_currentScanMode);
    
    // Listen to results and merge them
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      // Merge results into our collection
      for (final result in results) {
        final key = result.device.remoteId.toString();
        // Update with latest result (has most recent RSSI)
        _discoveredDevices[key] = result;
      }
      // Emit merged results
      _mergedResultsController.add(_discoveredDevices.values.toList());
    });

    // Start scan cycling - switch modes every 5 seconds for coverage
    _startScanCycling(timeout);
    
    return _mergedResultsController.stream;
  }

  /// Cycle through different scan modes for maximum device coverage
  void _startScanCycling(Duration totalTimeout) {
    _scanCycleTimer?.cancel();
    
    final cycleInterval = const Duration(seconds: 5);
    final endTime = DateTime.now().add(totalTimeout);
    
    _scanCycleTimer = Timer.periodic(cycleInterval, (timer) async {
      if (DateTime.now().isAfter(endTime)) {
        timer.cancel();
        return;
      }
      
      // Cycle to next scan mode
      _currentScanMode = (_currentScanMode + 1) % 4;
      
      try {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 200));
        await _startScanWithMode(_currentScanMode);
      } catch (e) {
        // Ignore scan cycling errors
      }
    });
  }

  /// Start scan with specific mode
  /// Mode 0: Low Latency - Fast discovery, high power
  /// Mode 1: Balanced - Medium speed, medium power
  /// Mode 2: Low Power - Slow but energy efficient
  /// Mode 3: Opportunistic - Piggyback on other app scans
  Future<void> _startScanWithMode(int mode) async {
    AndroidScanMode scanMode;
    
    switch (mode) {
      case 0:
        scanMode = AndroidScanMode.lowLatency;
        break;
      case 1:
        scanMode = AndroidScanMode.balanced;
        break;
      case 2:
        scanMode = AndroidScanMode.lowPower;
        break;
      case 3:
      default:
        scanMode = AndroidScanMode.opportunistic;
        break;
    }

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 60), // Long timeout, we manage it ourselves
      androidScanMode: scanMode,
      continuousUpdates: true,
      continuousDivisor: 1, // Report every result
      // Scan without filters for maximum discovery
      withServices: [],
      withNames: [],
      withKeywords: [],
      withRemoteIds: [],
    );
  }

  /// Alternative: Start parallel scans with different strategies
  /// Some devices work better with specific configurations
  Future<Stream<List<ScanResult>>> startParallelScanning({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _discoveredDevices.clear();
    
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 300));

    // Start with balanced mode (best for most devices)
    FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.balanced,
      continuousUpdates: true,
      continuousDivisor: 1,
    );

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final key = result.device.remoteId.toString();
        _discoveredDevices[key] = result;
      }
      _mergedResultsController.add(_discoveredDevices.values.toList());
    });

    // Schedule a scan restart with different mode after 3 seconds
    // This helps discover devices that weren't found in the first mode
    Future.delayed(const Duration(seconds: 3), () async {
      if (_scanSubscription != null) {
        try {
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 200));
          FlutterBluePlus.startScan(
            timeout: timeout - const Duration(seconds: 3),
            androidScanMode: AndroidScanMode.lowLatency,
            continuousUpdates: true,
            continuousDivisor: 1,
          );
        } catch (e) {
          // Ignore
        }
      }
    });

    // Schedule another restart with low power mode
    Future.delayed(const Duration(seconds: 8), () async {
      if (_scanSubscription != null) {
        try {
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 200));
          FlutterBluePlus.startScan(
            timeout: timeout - const Duration(seconds: 8),
            androidScanMode: AndroidScanMode.lowPower,
            continuousUpdates: true,
            continuousDivisor: 1,
          );
        } catch (e) {
          // Ignore
        }
      }
    });

    return _mergedResultsController.stream;
  }

  /// Stop scanning and clean up
  Future<void> stopScanning() async {
    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;
    
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
    
    _discoveredDevices.clear();
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
    _scanCycleTimer?.cancel();
    _advertisingRefreshTimer?.cancel();
    stopScanning();
    if (_isAdvertising) {
      stopAdvertising();
    }
    _mergedResultsController.close();
  }

  // ==================== UTILITY METHODS ====================

  /// Get device manufacturer name for debugging
  String getDeviceManufacturer() {
    // Common problematic manufacturers
    if (Platform.isAndroid) {
      return 'Android Device';
    }
    return 'iOS Device';
  }

  /// Check if device might have BLE scanning issues
  bool mightHaveScanningIssues() {
    // OnePlus, Nothing, Xiaomi, Oppo, Realme, Vivo often have issues
    // We can't easily detect manufacturer in Flutter, so we use aggressive scanning by default
    return Platform.isAndroid;
  }
}

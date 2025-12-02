import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request ALL Bluetooth and location permissions upfront
  Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  /// Request Bluetooth permissions for scanning (student side)
  static Future<bool> requestBluetoothScanPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  /// Request Bluetooth permissions for advertising (faculty side)
  static Future<bool> requestBluetoothAdvertisePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  /// Check current permission status
  static Future<Map<Permission, PermissionStatus>> checkBluetoothPermissions({
    bool forAdvertising = false,
  }) async {
    if (forAdvertising) {
      return {
        Permission.bluetoothAdvertise: await Permission.bluetoothAdvertise.status,
        Permission.bluetoothConnect: await Permission.bluetoothConnect.status,
        Permission.location: await Permission.location.status,
      };
    } else {
      return {
        Permission.bluetoothScan: await Permission.bluetoothScan.status,
        Permission.bluetoothConnect: await Permission.bluetoothConnect.status,
        Permission.location: await Permission.location.status,
      };
    }
  }

  /// Check if all required permissions are granted
  static Future<bool> hasBluetoothPermissions({
    bool forAdvertising = false,
  }) async {
    final statuses = await checkBluetoothPermissions(forAdvertising: forAdvertising);
    return statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );
  }

  /// Open app settings for manual permission granting
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}

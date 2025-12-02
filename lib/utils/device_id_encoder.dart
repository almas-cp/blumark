import 'dart:convert';

class DeviceIdEncoder {
  /// Encodes session ID to fit in BLE advertisement name (max ~8 chars)
  static String encodeForBle(String sessionId) {
    // Take first 8 characters of the UUID
    return sessionId.replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  /// Decodes BLE device name to extract session token
  static String? extractSessionToken(String deviceName, String prefix) {
    if (deviceName.startsWith(prefix)) {
      return deviceName.substring(prefix.length);
    }
    return null;
  }

  /// Encodes data for manufacturer data field
  static List<int> encodeManufacturerData(String sessionToken) {
    return utf8.encode(sessionToken);
  }

  /// Decodes manufacturer data to session token
  static String? decodeManufacturerData(List<int> data) {
    try {
      return utf8.decode(data);
    } catch (e) {
      return null;
    }
  }

  /// Validates a session token format
  static bool isValidSessionToken(String? token) {
    if (token == null || token.isEmpty) return false;
    // Should be 8 alphanumeric characters
    return RegExp(r'^[A-Z0-9]{8}$').hasMatch(token);
  }
}

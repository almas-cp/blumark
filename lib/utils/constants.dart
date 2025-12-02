class AppConstants {
  // Supabase Configuration
  static const String supabaseUrl = 'https://fiiuibpwxskeynkwxbdg.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_omf2pPedD36i57qJGfzp2Q_EHoyfCtj';

  // BLE Configuration
  static const String bleServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String bleDevicePrefix = 'BLU_'; // Prefix for BLE advertising name
  static const int bleManufacturerId = 0xFFFF;

  // Session Configuration
  static const List<String> departments = ['IT', 'CS'];
  static const List<String> batches = ['A', 'B'];
  static const List<int> years = [1, 2, 3, 4];
  static const List<int> hours = [1, 2, 3, 4, 5, 6];

  // SharedPreferences Keys
  static const String prefUserType = 'user_type';
  static const String prefUserId = 'user_id';
  static const String prefUserName = 'user_name';
  static const String prefUserEmail = 'user_email';
  static const String prefDepartment = 'department';
  static const String prefBatch = 'batch';
  static const String prefYear = 'year';
  static const String prefDeviceId = 'device_id';

  // Scan timeout
  static const Duration scanTimeout = Duration(seconds: 30);
}

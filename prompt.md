## Complete Flutter App Specification for AI IDE

### Required Packages (pubspec.yaml)

yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^1.34.5
  flutter_ble_peripheral: ^2.0.0
  supabase_flutter: ^2.10.3
  shared_preferences: ^2.2.3
  uuid: ^4.5.1
  permission_handler: ^11.3.1



### Android Manifest Permissions (android/app/src/main/AndroidManifest.xml)

xml
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>


### Supabase Database Schema

Create these tables in Supabase:

*Table: students*
sql
CREATE TABLE students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  batch TEXT NOT NULL,
  roll_number TEXT NOT NULL UNIQUE,
  bt_mac TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);


*Table: sessions*
sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  faculty_name TEXT NOT NULL,
  session_token TEXT NOT NULL UNIQUE,
  start_time TIMESTAMP DEFAULT NOW(),
  end_time TIMESTAMP,
  status TEXT DEFAULT 'active'
);


*Table: attendance_records*
sql
CREATE TABLE attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES sessions(id),
  student_id UUID REFERENCES students(id),
  student_name TEXT NOT NULL,
  roll_number TEXT NOT NULL,
  timestamp TIMESTAMP DEFAULT NOW(),
  UNIQUE(session_id, student_id)
);


### App Flow Implementation

## Screen 1: Onboarding Screen (onboarding_screen.dart)

*UI Elements:*
- Two large buttons: "I'm a Faculty" and "I'm a Student"
- Store selection in SharedPreferences with key user_role

*Logic:*
dart
if (tapped "Faculty") {
  save user_role = "faculty"
  navigate to FacultyHomeScreen
} else if (tapped "Student") {
  save user_role = "student"
  navigate to StudentRegistrationScreen
}


## Screen 2: Student Registration (student_registration_screen.dart)

*UI Elements:*
- TextFields: name, batch, roll_number
- Submit button

*Logic on Submit:*
1. Get device Bluetooth MAC address using FlutterBluePlus.adapterState and extract system Bluetooth address (store as unique identifier)
2. Insert into Supabase students table:
dart
await supabase.from('students').insert({
  'name': nameController.text,
  'batch': batchController.text,
  'roll_number': rollNumberController.text,
  'bt_mac': deviceMacAddress,
});

3. Store student_id in SharedPreferences with key student_id
4. Navigate to StudentHomeScreen

## Screen 3: Student Home Screen (student_home_screen.dart)

*UI Elements:*
- Welcome text with student name
- Large "Scan for Attendance" button
- Status indicator (Scanning/Success/Failed)

*Logic on Button Press:*
1. Request Bluetooth permissions using permission_handler
2. Start BLE scanning using flutter_blue_plus:
dart
FlutterBluePlus.startScan(timeout: Duration(seconds: 30));

3. Listen for scan results and filter for faculty beacon with custom service UUID (use UUID: 0000FFF0-0000-1000-8000-00805F9B34FB)
4. Extract session_token from advertised data (manufacturer data or device name)
5. Retrieve student_id and student info from SharedPreferences
6. Upload to Supabase:
dart
await supabase.from('attendance_records').insert({
  'session_id': extractedSessionId,
  'student_id': storedStudentId,
  'student_name': storedName,
  'roll_number': storedRollNumber,
});

7. Show success message and stop scanning
8. Handle errors with retry logic

## Screen 4: Faculty Home Screen (faculty_home_screen.dart)

*UI Elements:*
- TextField for faculty name
- "Start Attendance Session" button
- Real-time counter: "X students checked in"
- List view showing checked-in students (name, roll number, timestamp)
- "End Session" button

*Logic on "Start Session":*
1. Generate unique session_token using uuid.v4()
2. Insert into Supabase sessions table:
dart
final sessionId = await supabase.from('sessions').insert({
  'faculty_name': facultyNameController.text,
  'session_token': generatedToken,
  'status': 'active',
}).select().single();

3. Start BLE advertising using flutter_ble_peripheral:
dart
await FlutterBlePeripheral.advertise(
  advertiseData: AdvertiseData(
    serviceUuid: '0000FFF0-0000-1000-8000-00805F9B34FB',
    manufacturerData: utf8.encode(generatedToken),
    includeTxPowerLevel: true,
  ),
);

4. Subscribe to Supabase realtime:
dart
supabase
  .from('attendance_records')
  .stream(primaryKey: ['id'])
  .eq('session_id', sessionId)
  .listen((data) {
    setState(() {
      attendanceList = data;
    });
  });

5. Update UI counter and list dynamically

*Logic on "End Session":*
1. Stop BLE advertising: FlutterBlePeripheral.stop()
2. Update session in Supabase:
dart
await supabase.from('sessions').update({
  'end_time': DateTime.now().toIso8601String(),
  'status': 'completed',
}).eq('id', sessionId);

3. Show final attendance count

### Supabase Initialization (main.dart)

dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);


### App Entry Point Logic

Check SharedPreferences on app launch:
- If user_role exists → navigate to respective home screen
- Else → show OnboardingScreen

This specification is complete and ready for implementation by an AI IDE [1][2][3].

Citations:
[1] flutter_blue_plus | Flutter package - Pub.dev https://pub.dev/packages/flutter_blue_plus
[2] flutter_ble_peripheral - Bluetooth, NFC, Beacon - Flutter Gems https://fluttergems.dev/packages/flutter_ble_peripheral/
[3] supabase_flutter package - All Versions - Pub.dev https://pub.dev/packages/supabase_flutter/versions
[4] flutter_blue_plus package - All Versions - Pub.dev https://pub.dev/packages/flutter_blue_plus/versions
[5] Releases · chipweinberger/flutter_blue_plus - GitHub https://github.com/chipweinberger/flutter_blue_plus/releases
[6] Flutter blue plus no scan result since I upgraded to 1.32.8 from 1.5.2 https://stackoverflow.com/questions/78711691/flutter-blue-plus-no-scan-result-since-i-upgraded-to-1-32-8-from-1-5-2
[7] dongorias/Flutter-BluePlus - GitHub https://github.com/dongorias/Flutter-BluePlus
[8] Creating an App for Interacting with IoT Devices using BLE and ... https://blog.flutterflow.io/creating-an-app-for-interacting-with-any-iot-devices-using-ble/
[9] Using FlutterBlePeripheral in foreground service on Android https://stackoverflow.com/questions/79692993/using-flutterbleperipheral-in-foreground-service-on-android
[10] supabase_flutter - Flutter package in Authentication Providers & UI ... https://fluttergems.dev/packages/supabase_flutter/
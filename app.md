# BluMark - Bluetooth-Based Attendance System

## Overview

**BluMark** is a Flutter-based mobile application designed to automate attendance tracking using Bluetooth Low Energy (BLE) technology. The app enables faculty members to broadcast an attendance session via BLE, and students can scan for and mark their attendance by detecting the faculty's beacon signal. All data is synchronized with a cloud-based **Supabase** backend in real-time.

---

## Key Features

- 🔷 **BLE-Based Attendance** - Faculty devices broadcast attendance sessions via Bluetooth, and student devices scan for and detect these sessions.
- 👤 **Role-Based Access** - Three user types: Admin, Faculty, and Student, each with dedicated dashboards.
- ☁️ **Cloud Sync** - Real-time data synchronization with Supabase for attendance records, sessions, and user management.
- 📡 **Multi-Strategy BLE Scanning** - Uses multiple scanning modes (Low Latency, Balanced, Low Power, Opportunistic) to ensure compatibility across various Android devices (OnePlus, Nothing, Xiaomi, Samsung, Pixel, etc.).
- � **AR Head Counting** - Use Google ML Kit face detection to count heads in a classroom via camera, with progressive counting that handles 180° camera sweeps without duplicates.
- �📱 **Cross-Platform** - Built with Flutter, supports Android and iOS.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         BluMark App                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │    Admin     │  │   Faculty    │  │   Student    │           │
│  │  Dashboard   │  │  Dashboard   │  │  Dashboard   │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
│         │                 │                 │                   │
│         ▼                 ▼                 ▼                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     Services Layer                       │   │
│  │  ┌────────────────┐  ┌──────────────────┐  ┌──────────┐  │   │
│  │  │ BluetoothService│ │ SupabaseService  │  │Permission│  │   │
│  │  │  (BLE Central/  │ │  (Database +     │  │ Service  │  │   │
│  │  │   Peripheral)   │ │   Realtime)      │  │          │  │   │
│  │  └────────────────┘  └──────────────────┘  └──────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                  │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │      Supabase       │
                    │  ┌───────────────┐  │
                    │  │    student    │  │
                    │  │    faculty    │  │
                    │  │    session    │  │
                    │  │   attendance  │  │
                    │  │     admin     │  │
                    │  └───────────────┘  │
                    └─────────────────────┘
```

---

## User Roles & Workflows

### 1. **Admin**
- Manage faculty and student accounts
- Create, view, and delete faculty/students
- View all sessions and attendance records
- Access the Admin Dashboard

### 2. **Faculty**
- Start an attendance session for a class (department, batch, year, hour)
- Broadcast a BLE beacon with a unique session token
- View real-time attendance as students check in (via Supabase Realtime)
- End the session when done
- View session history

**Faculty Workflow:**
1. Login → Faculty Dashboard
2. Configure session (date, hour, department, batch, year)
3. Start Session → App broadcasts BLE beacon
4. Students scan and mark attendance
5. Real-time list updates as students check in
6. End Session → Stop BLE broadcast, mark session inactive

### 3. **Student**
- Scan for active attendance sessions via BLE
- Mark attendance by detecting the faculty's beacon
- View attendance history
- Dashboard shows active sessions for their class

**Student Workflow:**
1. Login → Student Dashboard
2. Tap "Scan for Attendance"
3. App scans for BLE beacons matching the session pattern
4. On detection, attendance is automatically marked in Supabase
5. Confirmation shown to the student

---

## Technology Stack

| Component               | Technology                              |
|-------------------------|-----------------------------------------|
| Framework               | Flutter (Dart)                          |
| BLE Scanning (Central)  | `flutter_blue_plus`                     |
| BLE Advertising (Periph)| `ble_peripheral`                        |
| Backend & Database      | Supabase (PostgreSQL + Realtime)        |
| Local Storage           | `shared_preferences`                    |
| Permissions             | `permission_handler`                    |
| Unique IDs              | `uuid`                                  |
| AR Face Detection       | `google_mlkit_face_detection`           |
| Camera                  | `camera`                                |

---

## Database Schema

### `student`
| Column      | Type      | Description                |
|-------------|-----------|----------------------------|
| id          | UUID (PK) | Unique student ID          |
| name        | TEXT      | Student's name             |
| email       | TEXT      | Login email                |
| password    | TEXT      | Login password             |
| department  | TEXT      | Student's department       |
| batch       | TEXT      | Batch identifier           |
| year        | INT       | Current year               |
| roll_number | INT       | Roll number                |
| created_at  | TIMESTAMP | Account creation time      |

### `faculty`
| Column     | Type      | Description           |
|------------|-----------|------------------------|
| id         | UUID (PK) | Unique faculty ID      |
| name       | TEXT      | Faculty name           |
| email      | TEXT      | Login email            |
| password   | TEXT      | Login password         |
| created_at | TIMESTAMP | Account creation time  |

### `session`
| Column     | Type      | Description                        |
|------------|-----------|-------------------------------------|
| id         | UUID (PK) | Unique session ID                   |
| faculty_id | UUID (FK) | References faculty.id               |
| date       | DATE      | Session date                        |
| hour       | INT       | Class hour                          |
| department | TEXT      | Target department                   |
| batch      | TEXT      | Target batch                        |
| year       | INT       | Target year                         |
| hex_ssid   | TEXT      | BLE session token (unique beacon ID)|
| is_active  | BOOLEAN   | Whether session is ongoing          |
| created_at | TIMESTAMP | Session creation time               |

### `attendance`
| Column     | Type      | Description                        |
|------------|-----------|-------------------------------------|
| id         | UUID (PK) | Unique attendance record ID         |
| student_id | UUID (FK) | References student.id               |
| session_id | UUID (FK) | References session.id               |
| attendance | INT       | Attendance flag (1 = present)       |
| marked_at  | TIMESTAMP | Time attendance was marked          |

### `admin`
| Column   | Type      | Description         |
|----------|-----------|----------------------|
| id       | UUID (PK) | Unique admin ID      |
| username | TEXT      | Login username       |
| password | TEXT      | Login password       |

---

## BLE Communication

### Advertising (Faculty Side)
When a faculty starts a session:
1. A unique session token is generated (UUID-based hex string)
2. The device starts BLE advertising with:
   - **Service UUID:** `0000FFF0-0000-1000-8000-00805F9B34FB`
   - **Local Name:** `BM_<session_token>`
   - **Manufacturer Data:** Encoded session token
3. Multiple advertising strategies are tried for compatibility

### Scanning (Student Side)
When a student scans for attendance:
1. App performs BLE scan using multiple modes (Low Latency → Balanced → Low Power → Opportunistic)
2. Looks for devices with:
   - Local name starting with `BM_` prefix
   - Known service UUID
   - Matching manufacturer data
3. Extracts session token from the beacon
4. Verifies session exists and is active in Supabase
5. Marks attendance for the student

---

## Project Structure

```
lib/
├── main.dart                 # App entry point, routing, initialization
├── models/
│   ├── admin.dart            # Admin data model
│   ├── attendance.dart       # Attendance record model
│   ├── faculty.dart          # Faculty data model
│   ├── session.dart          # Attendance session model
│   └── student.dart          # Student data model
├── screens/
│   ├── login_screen.dart     # Login screen for all user types
│   ├── admin/
│   │   └── admin_dashboard.dart   # Admin management UI
│   ├── faculty/
│   │   ├── faculty_dashboard.dart   # Faculty session management
│   │   └── head_counting_screen.dart # AR head counting with face detection
│   └── student/
│       └── student_dashboard.dart # Student attendance scanning
├── services/
│   ├── bluetooth_service.dart    # BLE scanning & advertising
│   ├── permission_service.dart   # Runtime permission handling
│   └── supabase_service.dart     # Database operations & realtime
└── utils/
    ├── constants.dart            # App constants, Supabase keys
    └── device_id_encoder.dart    # Session token encoding/decoding
```

---

## Key Dependencies

```yaml
dependencies:
  flutter_blue_plus: ^1.34.5     # BLE Central (scanning)
  ble_peripheral: ^2.4.0          # BLE Peripheral (advertising)
  supabase_flutter: ^2.10.3       # Backend & Realtime
  shared_preferences: ^2.2.3      # Local storage
  uuid: ^4.5.1                    # Unique ID generation
  permission_handler: ^11.3.1     # Runtime permissions
  google_mlkit_face_detection: ^0.13.1  # AR face detection
  camera: ^0.11.3                 # Camera access for head counting
```

---

## Platform Permissions

### Android (`AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS (`Info.plist`)
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `NSLocationWhenInUseUsageDescription`

---

## Getting Started

1. **Clone the repository**
2. **Configure Supabase:**
   - Create tables as per the schema above
   - Update `utils/constants.dart` with your Supabase URL and anon key
3. **Install dependencies:**
   ```bash
   flutter pub get
   ```
4. **Run the app:**
   ```bash
   flutter run
   ```

---


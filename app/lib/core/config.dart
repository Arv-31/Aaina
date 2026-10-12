// config.dart: the ONE place for the server address (rule 7).
//
// At the expo the phone joins the laptop's hotspot and talks to the backend
// on that laptop. Windows Mobile Hotspot gives the laptop 192.168.137.1.
// If you use a different network, put the laptop's IP here (run.py prints it).
//
// The address can also be changed inside the app (Connect sheet) without
// rebuilding the APK. That choice is saved on the phone and wins over the
// default below. Handy because the expo laptop is a different machine.
//
// When the camera screen runs in a browser on the laptop itself (laptop
// webcam), it talks to the backend on the same machine: localhost.
//
// No secrets go in this file: the app has no API keys (rule 4).

class AppConfig {
  /// Default address used by the Android app on the phone.
  static const serverUrl = 'http://192.168.137.1:8000';

  /// Used by the web version running on the server laptop.
  static const laptopServerUrl = 'http://localhost:8000';
}

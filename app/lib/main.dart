// main.dart: app entry point.
//
// Milestone 4: the app opens straight into the camera screen. Welcome,
// login and signup screens come in Milestone 7.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'features/camera_ar/camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only: keeps the camera-to-screen math simple.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Light status-bar icons over the dark UI / camera.
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(const AainaApp());
}

class AainaApp extends StatelessWidget {
  const AainaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aaina',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const CameraScreen(),
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/themes/app_theme.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    print('Starting Lockdown CBT application...');

    // Load environment variables
    await dotenv.load(fileName: '.env');
    print('Environment variables loaded');

    // Initialize GetStorage
    await GetStorage.init();
    print('GetStorage initialized');

    // Initialize window_manager only on desktop platforms (Windows, macOS, Linux)
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await windowManager.ensureInitialized();

      const WindowOptions windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(800, 600),
        center: true,
        title: 'Lockdown CBT',
        skipTaskbar: false,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    print('Launching app...');
    runApp(const LockdownApp());
  } catch (e, stackTrace) {
    print('ERROR during initialization: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}

class LockdownApp extends StatelessWidget {
  const LockdownApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Lockdown CBT',
      theme: AppTheme.lightTheme,
      initialRoute: AppRoutes.SPLASH,
      getPages: AppPages.pages,
      debugShowCheckedModeBanner: false,
      defaultTransition: Transition.noTransition,
    );
  }
}

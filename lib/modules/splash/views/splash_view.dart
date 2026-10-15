import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/app/routes/app_routes.dart';

class SplashView extends StatefulWidget {
  const SplashView({Key? key}) : super(key: key);

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Gunakan timer langsung di state widget, terbukti 100% reliabel di Flutter Desktop
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Get.offAllNamed(AppRoutes.SETUP_URL);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 100, color: Theme.of(context).primaryColor),
            const SizedBox(height: 20),
            Text(
              'Lockdown CBT',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Initializing...'),
            const SizedBox(height: 30),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            // Tombol darurat/manual jika user ingin langsung masuk atau jika auto-navigasi terhalang
            TextButton(
              onPressed: () {
                Get.offAllNamed(AppRoutes.SETUP_URL);
              },
              child: const Text('Continue to Setup ->'),
            ),
          ],
        ),
      ),
    );
  }
}

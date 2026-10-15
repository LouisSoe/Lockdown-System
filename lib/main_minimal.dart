import 'package:flutter/material.dart';

void main() {
  runApp(const MinimalTestApp());
}

class MinimalTestApp extends StatelessWidget {
  const MinimalTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimal Test',
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text('Minimal Test App'),
              SizedBox(height: 20),
              Text('If you see this, Flutter is working!'),
            ],
          ),
        ),
      ),
    );
  }
}

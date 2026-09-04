import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/modules/setup/controllers/setup_controller.dart';

class SetupUrlView extends GetView<SetupController> {
  const SetupUrlView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Exam'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter Exam URL',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller.urlController,
              decoration: const InputDecoration(
                labelText: 'Exam URL',
                hintText: 'https://forms.google.com/...',
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 30),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lockdown Features',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildFeatureItem(Icons.fullscreen, 'Fullscreen Mode'),
                    _buildFeatureItem(Icons.block, 'Block App Switching'),
                    _buildFeatureItem(Icons.keyboard_hide, 'Disable Shortcuts'),
                    _buildFeatureItem(Icons.content_paste_off, 'Block Copy/Paste'),
                    _buildFeatureItem(Icons.security, 'Kiosk Mode'),
                    _buildFeatureItem(Icons.monitor, 'Activity Monitoring'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Once exam starts, you cannot exit without password from administrator.',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            Obx(() => ElevatedButton(
              onPressed: controller.isLoading.value 
                  ? null 
                  : controller.startExam,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: controller.isLoading.value
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Start Exam', style: TextStyle(fontSize: 18)),
            )),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}

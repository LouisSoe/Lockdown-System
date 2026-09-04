import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/modules/exam/controllers/exam_controller.dart';

class ExamView extends GetView<ExamController> {
  const ExamView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        controller.showExitDialog();
        return false;
      },
      child: Scaffold(
        body: Column(
          children: [
            _buildStatusBar(context),
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(controller.examUrl),
                    ),
                    initialSettings: controller.webViewService.getSettings(),
                    onWebViewCreated: controller.onWebViewCreated,
                    onLoadStart: controller.webViewService.handleLoadStart,
                    onLoadStop: controller.webViewService.handleLoadStop,
                    onProgressChanged: controller.webViewService.handleProgressChanged,
                    onLoadError: controller.webViewService.handleLoadError,
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      this.controller.webViewService.shouldOverrideUrlLoading(navigationAction);
                      return NavigationActionPolicy.ALLOW;
                    },
                    onDownloadStartRequest: (controller, request) {
                      this.controller.webViewService.handleDownloadStart(request);
                    },
                    onCreateWindow: (controller, createWindowAction) async {
                      return this.controller.webViewService.handleCreateWindow(createWindowAction);
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      this.controller.webViewService.handleConsoleMessage(consoleMessage);
                    },
                  ),
                  Obx(() => controller.webViewService.isLoading.value
                      ? Container(
                          color: Colors.white,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading exam...',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Obx(() => LinearProgressIndicator(
                                  value: controller.webViewService.loadProgress.value,
                                )),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusBar(BuildContext context) {
    return Container(
      height: 50,
      color: Colors.blue.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            'LOCKDOWN MODE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Obx(() => Text(
            controller.remainingTime.value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          )),
          const SizedBox(width: 20),
          Obx(() => Icon(
            controller.webViewService.isLoading.value
                ? Icons.hourglass_empty
                : Icons.check_circle,
            color: Colors.white,
            size: 20,
          )),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            onPressed: controller.showExitDialog,
            tooltip: 'Exit Exam',
          ),
        ],
      ),
    );
  }
}

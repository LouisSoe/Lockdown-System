import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';

class WebViewService extends GetxService {
  late InAppWebViewController webViewController;
  
  final isLoading = true.obs;
  final canGoBack = false.obs;
  final canGoForward = false.obs;
  final currentUrl = ''.obs;
  final loadProgress = 0.0.obs;
  
  // WebView settings
  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      // JavaScript
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      
      // Media
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      
      // Security
      allowFileAccess: false,
      allowContentAccess: false,
      allowUniversalAccessFromFileURLs: false,
      allowFileAccessFromFileURLs: false,
      
      // Zoom
      supportZoom: false,
      builtInZoomControls: false,
      displayZoomControls: false,
      
      // Cache
      cacheEnabled: true,
      clearCache: false,
      
      // DevTools - disabled in production
      debuggingEnabled: false,
      
      // Downloads
      useOnDownloadStart: true,
      
      // Display
      transparentBackground: false,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: true,
      
      // Hardware acceleration
      hardwareAcceleration: true,
      
      // Mixed content (allow HTTPS to load HTTP resources if needed)
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      
      // User agent (optional - can be customized)
      userAgent: 'LockdownCBT/1.0',
    );
  }
  
  // Load start handler
  void handleLoadStart(InAppWebViewController controller, WebUri? url) {
    isLoading.value = true;
    currentUrl.value = url?.toString() ?? '';
    loadProgress.value = 0.0;
  }
  
  // Load stop handler
  void handleLoadStop(InAppWebViewController controller, WebUri? url) {
    isLoading.value = false;
    currentUrl.value = url?.toString() ?? '';
    loadProgress.value = 1.0;
    updateNavigationState();
  }
  
  // Progress changed handler
  void handleProgressChanged(InAppWebViewController controller, int progress) {
    loadProgress.value = progress / 100.0;
  }
  
  // Load error handler
  void handleLoadError(
    InAppWebViewController controller,
    WebUri? url,
    int code,
    String message,
  ) {
    print('WebView Load Error: $code - $message');
    // Security logger will be integrated later
  }
  
  // Navigation handler
  NavigationActionPolicy shouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) {
    final url = navigationAction.request.url?.toString() ?? '';
    
    // Log navigation attempt (will integrate with security logger later)
    print('Navigation attempt: $url');
    
    // For now, allow all URLs for flexibility
    // Later we can add whitelist/blacklist functionality
    return NavigationActionPolicy.ALLOW;
  }
  
  // Download handler
  void handleDownloadStart(DownloadStartRequest downloadStartRequest) {
    final url = downloadStartRequest.url.toString();
    print('Download blocked: $url');
    
    // Log download attempt (will integrate with security logger later)
    Get.snackbar(
      'Download Blocked',
      'Downloads are not allowed during exam',
      snackPosition: SnackPosition.TOP,
    );
  }
  
  // Create window handler (popups)
  bool handleCreateWindow(CreateWindowAction createWindowAction) {
    final url = createWindowAction.request.url?.toString();
    print('Popup blocked: $url');
    
    Get.snackbar(
      'Popup Blocked',
      'Popups are not allowed during exam',
      snackPosition: SnackPosition.TOP,
    );
    
    return false; // Don't create new window
  }
  
  // Update navigation state
  Future<void> updateNavigationState() async {
    canGoBack.value = await webViewController.canGoBack();
    canGoForward.value = await webViewController.canGoForward();
  }
  
  // Navigation methods
  Future<void> goBack() async {
    if (await webViewController.canGoBack()) {
      await webViewController.goBack();
    }
  }
  
  Future<void> goForward() async {
    if (await webViewController.canGoForward()) {
      await webViewController.goForward();
    }
  }
  
  Future<void> reload() async {
    await webViewController.reload();
  }
  
  // Inject JavaScript bridge
  Future<void> injectJavaScriptBridge() async {
    await webViewController.evaluateJavascript(source: '''
      // Create Lockdown Bridge for communication with Flutter
      window.LockdownBridge = {
        finishExam: function(data) {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('finishExam', data);
          }
        },
        timeUp: function() {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('timeUp');
          }
        },
        sendMessage: function(message) {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('message', message);
          }
        },
        getVersion: function() {
          return '1.0.0';
        }
      };
      
      console.log('LockdownBridge injected successfully');
    ''');
  }
  
  // Console message handler
  void handleConsoleMessage(ConsoleMessage consoleMessage) {
    print('WebView Console [${consoleMessage.messageLevel.name}]: ${consoleMessage.message}');
  }
  
  // Cleanup
  @override
  void onClose() {
    // Clean up resources if needed
    super.onClose();
  }
}

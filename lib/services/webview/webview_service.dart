import 'dart:io' show Platform;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

class WebViewService extends GetxService {
  late InAppWebViewController webViewController;
  
  final isLoading = true.obs;
  final canGoBack = false.obs;
  final canGoForward = false.obs;
  final currentUrl = ''.obs;
  final loadProgress = 0.0.obs;
  final hasLoadError = false.obs;
  final lastErrorCode = 0.obs;
  final lastErrorMessage = ''.obs;

  /// User-Agent standar Chrome agar Google OAuth tidak memblokir login dengan error "Browser tidak didukung"
  static String getDefaultUserAgent() {
    try {
      if (Platform.isAndroid) {
        return 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';
      } else if (Platform.isWindows) {
        return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
      } else if (Platform.isIOS) {
        return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
      }
    } catch (_) {}
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
  }
  
  // WebView settings
  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      // JavaScript
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: false,

      // Storage & Cookies untuk Google Login / SSO
      domStorageEnabled: true,
      databaseEnabled: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,

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

      // Downloads
      useOnDownloadStart: true,

      // Context menu — blokir klik kanan (desktop) dan long press (mobile)
      disableContextMenu: true,
      disableLongPressContextMenuOnLinks: true,

      // Display
      transparentBackground: false,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: true,

      // Hardware acceleration
      hardwareAcceleration: true,

      // Mixed content (allow HTTPS to load HTTP resources if needed)
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,

      // User agent — standard Chrome browser agar diterima Google OAuth
      userAgent: getDefaultUserAgent(),
    );
  }
  
  // Load start handler
  void handleLoadStart(InAppWebViewController controller, WebUri? url) {
    isLoading.value = true;
    hasLoadError.value = false;
    lastErrorMessage.value = '';
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
    Uri? url,
    int code,
    String message,
  ) {
    isLoading.value = false;
    hasLoadError.value = true;
    lastErrorCode.value = code;
    lastErrorMessage.value = message;
    print('WebView Load Error: $code - $message');
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
  
  // Create window handler (popups / SSO Google Login)
  bool handleCreateWindow(CreateWindowAction createWindowAction) {
    final request = createWindowAction.request;
    final url = request.url?.toString() ?? '';
    print('Create window request: $url');

    // Jika window.open dipanggil (misal popup OAuth Google/SSO),
    // muat URL tersebut langsung di WebView yang sama agar login berjalan mulus
    if (request.url != null) {
      webViewController.loadUrl(urlRequest: request);
      return false; // Return false agar WebView tidak mengharapkan windowId terpisah
    }

    return false;
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
    hasLoadError.value = false;
    lastErrorMessage.value = '';
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
    print('WebView Console [${consoleMessage.messageLevel.toString()}]: ${consoleMessage.message}');
  }
  
  // Cleanup WebView safely before unmount
  Future<void> disposeWebView() async {
    try {
      await webViewController.stopLoading();
    } catch (_) {
      // Controller might already be disposed or unattached
    }
  }

  // Cleanup
  @override
  void onClose() {
    disposeWebView();
    super.onClose();
  }
}

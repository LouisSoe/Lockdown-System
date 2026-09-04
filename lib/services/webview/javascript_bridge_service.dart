import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';

class JavaScriptBridgeService extends GetxService {
  late InAppWebViewController controller;
  
  // JavaScript handler callbacks
  final Map<String, Function(List<dynamic>)> _handlers = {};
  
  void setController(InAppWebViewController webViewController) {
    controller = webViewController;
    _registerHandlers();
  }
  
  // Register all JavaScript handlers
  void _registerHandlers() {
    // Finish exam handler
    controller.addJavaScriptHandler(
      handlerName: 'finishExam',
      callback: (args) {
        print('Exam finished from WebView: $args');
        if (_handlers.containsKey('finishExam')) {
          _handlers['finishExam']!(args);
        }
      },
    );
    
    // Time up handler
    controller.addJavaScriptHandler(
      handlerName: 'timeUp',
      callback: (args) {
        print('Time up from WebView');
        if (_handlers.containsKey('timeUp')) {
          _handlers['timeUp']!(args);
        }
      },
    );
    
    // Generic message handler
    controller.addJavaScriptHandler(
      handlerName: 'message',
      callback: (args) {
        print('Message from WebView: $args');
        if (_handlers.containsKey('message')) {
          _handlers['message']!(args);
        }
      },
    );
    
    // Ready handler (when exam page is ready)
    controller.addJavaScriptHandler(
      handlerName: 'ready',
      callback: (args) {
        print('WebView ready');
        if (_handlers.containsKey('ready')) {
          _handlers['ready']!(args);
        }
      },
    );
  }
  
  // Register custom handler
  void registerHandler(String name, Function(List<dynamic>) callback) {
    _handlers[name] = callback;
  }
  
  // Send message to WebView
  Future<void> sendToWebView(String method, dynamic data) async {
    try {
      await controller.evaluateJavascript(source: '''
        if (window.LockdownBridge && typeof window.LockdownBridge.$method === 'function') {
          window.LockdownBridge.$method($data);
        }
      ''');
    } catch (e) {
      print('Error sending to WebView: $e');
    }
  }
  
  // Inject custom JavaScript
  Future<void> injectScript(String script) async {
    try {
      await controller.evaluateJavascript(source: script);
    } catch (e) {
      print('Error injecting script: $e');
    }
  }
  
  // Get value from WebView
  Future<dynamic> getValueFromWebView(String script) async {
    try {
      return await controller.evaluateJavascript(source: script);
    } catch (e) {
      print('Error getting value from WebView: $e');
      return null;
    }
  }
}

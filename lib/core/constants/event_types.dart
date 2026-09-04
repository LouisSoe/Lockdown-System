class EventTypes {
  // Focus events
  static const String FOCUS_LOST = 'FOCUS_LOST';
  static const String FOCUS_GAINED = 'FOCUS_GAINED';
  
  // App switching events
  static const String APP_SWITCH_ATTEMPT = 'APP_SWITCH_ATTEMPT';
  
  // Shortcut events
  static const String SHORTCUT_BLOCKED = 'SHORTCUT_BLOCKED';
  
  // Process events
  static const String PROCESS_VIOLATION = 'PROCESS_VIOLATION';
  
  // Display events
  static const String DISPLAY_CHANGED = 'DISPLAY_CHANGED';
  
  // Network events
  static const String NETWORK_VIOLATION = 'NETWORK_VIOLATION';
  
  // Clipboard events
  static const String CLIPBOARD_ACTIVITY = 'CLIPBOARD_ACTIVITY';
  
  // Screenshot events
  static const String SCREENSHOT_TAKEN = 'SCREENSHOT_TAKEN';
  
  // WebView events
  static const String WEBVIEW_ERROR = 'WEBVIEW_ERROR';
  static const String NAVIGATION_ATTEMPT = 'NAVIGATION_ATTEMPT';
  static const String DOWNLOAD_BLOCKED = 'DOWNLOAD_BLOCKED';
  static const String POPUP_BLOCKED = 'POPUP_BLOCKED';
  
  // Exam events
  static const String EXAM_STARTED = 'EXAM_STARTED';
  static const String EXAM_FINISHED = 'EXAM_FINISHED';
  static const String EXIT_ATTEMPT = 'EXIT_ATTEMPT';
}

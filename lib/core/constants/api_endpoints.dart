class ApiEndpoints {
  // Activation endpoints
  static const String verifyToken = '/activation/verify';
  static const String completeActivation = '/activation/complete';

  // Token validation endpoints (Violation & Exit)
  static const String validateToken = '/tokens/validate';
  static const String validateTokenAlias = '/activation/validate-token';

  // Exam endpoints
  static const String startExam = '/exam/start';
  static const String finishExam = '/exam/finish';

  // Monitoring endpoints
  static const String uploadEvents = '/monitoring/events';
  static const String uploadScreenshot = '/monitoring/screenshot';

  // Config endpoints
  static const String getConfig = '/exam/config';
}

class ApiEndpoints {
  // Activation endpoints
  static const String verifyToken = '/activation/verify';
  static const String completeActivation = '/activation/complete';

  // Exam endpoints
  static const String startExam = '/exam/start';
  static const String finishExam = '/exam/finish';
  static const String validatePassword = '/exam/validate-password';

  // Monitoring endpoints
  static const String uploadEvents = '/monitoring/events';
  static const String uploadScreenshot = '/monitoring/screenshot';

  // Config endpoints
  static const String getConfig = '/exam/config';
}

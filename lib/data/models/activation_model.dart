class ActivationModel {
  final bool valid;
  final String message;
  final int? sessionId;
  final String? studentName;
  final String? examName;
  final String? redirectUrl;
  final int? maxViolations;
  final bool hasViolationLimit;
  final String expiresAt;
  final int remainingSeconds;

  ActivationModel({
    required this.valid,
    required this.message,
    this.sessionId,
    this.studentName,
    this.examName,
    this.redirectUrl,
    this.maxViolations,
    this.hasViolationLimit = true,
    required this.expiresAt,
    required this.remainingSeconds,
  });

  factory ActivationModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : <String, dynamic>{};

    return ActivationModel(
      valid: data['valid'] as bool? ?? (json['success'] as bool? ?? false),
      message: data['message']?.toString() ?? json['message']?.toString() ?? '',
      sessionId: data['session_id'] is int
          ? data['session_id'] as int
          : int.tryParse(data['session_id']?.toString() ?? ''),
      studentName: data['student_name']?.toString(),
      examName: data['exam_name']?.toString(),
      redirectUrl: data['redirect_url']?.toString(),
      maxViolations: data['max_violations'] is int
          ? data['max_violations'] as int
          : int.tryParse(data['max_violations']?.toString() ?? ''),
      hasViolationLimit: data['has_violation_limit'] as bool? ??
          (data['max_violations'] != null),
      expiresAt: data['expires_at']?.toString() ?? '',
      remainingSeconds: int.tryParse(data['remaining_seconds']?.toString() ?? '0') ?? 0,
    );
  }
}

class ActivationCompleteModel {
  final bool success;
  final String message;
  final int? sessionId;
  final String status;
  final String? completedAt;
  final int durationSeconds;

  ActivationCompleteModel({
    required this.success,
    required this.message,
    this.sessionId,
    required this.status,
    this.completedAt,
    required this.durationSeconds,
  });

  factory ActivationCompleteModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : <String, dynamic>{};

    return ActivationCompleteModel(
      success: json['success'] as bool? ?? true,
      message: json['message']?.toString() ?? '',
      sessionId: data['session_id'] is int
          ? data['session_id'] as int
          : int.tryParse(data['session_id']?.toString() ?? ''),
      status: data['status']?.toString() ?? '',
      completedAt: data['completed_at']?.toString(),
      durationSeconds: int.tryParse(data['duration_seconds']?.toString() ?? '0') ?? 0,
    );
  }
}


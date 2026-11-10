class TokenValidationData {
  final bool valid;
  final String token;
  final String type; // 'violation' | 'exit'
  final bool isActive;
  final String? usedAt;
  final String? expiresAt;
  final int? remainingSeconds;
  final int usageCount;
  final int? examUrlId;
  final String? examName;

  TokenValidationData({
    required this.valid,
    required this.token,
    required this.type,
    required this.isActive,
    this.usedAt,
    this.expiresAt,
    this.remainingSeconds,
    required this.usageCount,
    this.examUrlId,
    this.examName,
  });

  factory TokenValidationData.fromJson(Map<String, dynamic> json) {
    return TokenValidationData(
      valid: json['valid'] as bool? ?? false,
      token: json['token']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      isActive: json['is_active'] as bool? ?? false,
      usedAt: json['used_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      remainingSeconds: json['remaining_seconds'] is int
          ? json['remaining_seconds'] as int
          : int.tryParse(json['remaining_seconds']?.toString() ?? ''),
      usageCount: json['usage_count'] is int
          ? json['usage_count'] as int
          : int.tryParse(json['usage_count']?.toString() ?? '0') ?? 0,
      examUrlId: json['exam_url_id'] is int
          ? json['exam_url_id'] as int
          : int.tryParse(json['exam_url_id']?.toString() ?? ''),
      examName: json['exam_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'valid': valid,
        'token': token,
        'type': type,
        'is_active': isActive,
        'used_at': usedAt,
        'expires_at': expiresAt,
        'remaining_seconds': remainingSeconds,
        'usage_count': usageCount,
        'exam_url_id': examUrlId,
        'exam_name': examName,
      };
}

class TokenValidationResponse {
  final bool success;
  final String message;
  final TokenValidationData? data;

  TokenValidationResponse({
    required this.success,
    required this.message,
    this.data,
  });

  factory TokenValidationResponse.fromJson(Map<String, dynamic> json) {
    return TokenValidationResponse(
      success: json['success'] as bool? ?? false,
      message: json['message']?.toString() ?? '',
      data: json['data'] is Map<String, dynamic>
          ? TokenValidationData.fromJson(json['data'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'data': data?.toJson(),
      };
}


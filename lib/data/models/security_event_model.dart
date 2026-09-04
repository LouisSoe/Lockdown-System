class SecurityEventModel {
  final String id;
  final String type;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final String? screenshotId;
  
  SecurityEventModel({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.data,
    this.screenshotId,
  });
  
  factory SecurityEventModel.fromJson(Map<String, dynamic> json) {
    return SecurityEventModel(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      data: json['data'] ?? {},
      screenshotId: json['screenshot_id'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    if (screenshotId != null) 'screenshot_id': screenshotId,
  };
}

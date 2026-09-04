class ExamSessionModel {
  final String sessionId;
  final String examUrl;
  final int duration; // in minutes
  final DateTime startTime;
  
  ExamSessionModel({
    required this.sessionId,
    required this.examUrl,
    required this.duration,
    required this.startTime,
  });
  
  factory ExamSessionModel.fromJson(Map<String, dynamic> json) {
    return ExamSessionModel(
      sessionId: json['session_id'] ?? '',
      examUrl: json['exam_url'] ?? '',
      duration: json['duration'] ?? 90,
      startTime: json['start_time'] != null 
          ? DateTime.parse(json['start_time'])
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'exam_url': examUrl,
    'duration': duration,
    'start_time': startTime.toIso8601String(),
  };
}

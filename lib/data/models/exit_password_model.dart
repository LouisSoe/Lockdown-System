class ExitPasswordModel {
  final bool isValid;
  final String? message;
  
  ExitPasswordModel({
    required this.isValid,
    this.message,
  });
  
  factory ExitPasswordModel.fromJson(Map<String, dynamic> json) {
    return ExitPasswordModel(
      isValid: json['is_valid'] ?? false,
      message: json['message'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'is_valid': isValid,
    if (message != null) 'message': message,
  };
}

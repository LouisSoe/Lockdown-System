import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lockdown_engine/core/constants/event_types.dart';
import 'package:lockdown_engine/data/models/security_event_model.dart';
import 'package:lockdown_engine/data/repositories/monitoring_repository.dart';
import 'package:uuid/uuid.dart';

class SecurityLoggerService extends GetxService {
  final MonitoringRepository _monitoringRepo = MonitoringRepository();
  final _eventQueue = <SecurityEventModel>[].obs;
  
  Timer? _uploadTimer;
  String? currentSessionId;
  bool _isUploading = false;
  
  void startLogging(String sessionId) {
    currentSessionId = sessionId;
    _uploadTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      uploadBatch();
    });
    
    print('✓ Security logging started for session: $sessionId');
  }
  
  void logEvent({
    required String type,
    required Map<String, dynamic> data,
    bool captureScreenshot = false,
    String? screenshotId,
  }) {
    if (currentSessionId == null) {
      print('⚠ Cannot log event: No active session');
      return;
    }
    
    final eventId = const Uuid().v4();
    
    final event = SecurityEventModel(
      id: eventId,
      type: type,
      timestamp: DateTime.now(),
      data: data,
      screenshotId: screenshotId,
    );
    
    _eventQueue.add(event);
    print('📝 Event logged: $type (Queue: ${_eventQueue.length})');
    
    // Upload if queue is full
    if (_eventQueue.length >= 10) {
      uploadBatch();
    }
  }
  
  Future<void> uploadBatch() async {
    if (_eventQueue.isEmpty || currentSessionId == null || _isUploading) {
      return;
    }
    
    _isUploading = true;
    
    try {
      final events = List<SecurityEventModel>.from(_eventQueue);
      await _monitoringRepo.uploadEvents(currentSessionId!, events);
      
      _eventQueue.clear();
      print('✓ Uploaded ${events.length} events');
    } catch (e) {
      print('✗ Upload batch error: $e');
      // Keep events in queue for retry
    } finally {
      _isUploading = false;
    }
  }
  
  Future<void> stopLogging() async {
    _uploadTimer?.cancel();
    
    // Upload remaining events
    if (_eventQueue.isNotEmpty) {
      await uploadBatch();
    }
    
    currentSessionId = null;
    print('✓ Security logging stopped');
  }
  
  int getQueueSize() => _eventQueue.length;
  
  @override
  void onClose() {
    _uploadTimer?.cancel();
    super.onClose();
  }
}

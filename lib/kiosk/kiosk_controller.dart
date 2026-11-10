import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class KioskStatus {
  const KioskStatus(this.raw);
  final Map<String, dynamic> raw;

  static const empty = KioskStatus({});

  bool flag(String key) => raw[key] == true;
  bool get active => flag('active');
  bool get pinned => flag('pinned');
  bool get guard => flag('guard');
  bool get gateOpen => flag('gateOpen');
  bool get prereqOk => flag('prereqOk');
  String get state => (raw['state'] as String?) ?? 'PREFLIGHT';
  int get violations => (raw['violations'] as int?) ?? 0;
  int get maxViolations => (raw['maxViolations'] as int?) ?? 2;
  bool get hasViolationLimit => raw['hasViolationLimit'] != false;
  bool get isBlocked =>
      raw['isBlocked'] == true || (hasViolationLimit && violations > maxViolations);
  bool get isLockedOut => raw['isLockedOut'] == true;
  List<String> get missing =>
      List<String>.from((raw['missing'] as List?) ?? const []);
}

enum KioskSetting { guard, overlay, battery, usage, home, notif, app }

class KioskController extends ChangeNotifier with WidgetsBindingObserver {
  KioskController() {
    WidgetsBinding.instance.addObserver(this);
    _sub = _events.receiveBroadcastStream().listen(_onStatus, onError: (_) {});
    refresh();
  }

  static const _method = MethodChannel('exam_kiosk/native');
  static const _events = EventChannel('exam_kiosk/events');

  StreamSubscription<dynamic>? _sub;
  KioskStatus status = KioskStatus.empty;
  bool _examActive = false;
  bool get isExamActive => _examActive;

  void _onStatus(dynamic data) {
    if (data is Map) {
      status = KioskStatus(Map<String, dynamic>.from(data));
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      final data = await _method.invokeMethod<Map<dynamic, dynamic>>('getStatus');
      if (data != null) _onStatus(data);
    } on MissingPluginException {
      // bukan Android: status tetap kosong
    } catch (_) {}
  }

  Future<void> start({
    required String apiBase,
    required String token,
    required String examId,
    required String studentId,
    int? maxViolations,
    bool? hasViolationLimit,
    List<String> allowedPackages = const [],
  }) async {
    try {
      await _method.invokeMethod('startExam', {
        'apiBase': apiBase,
        'token': token,
        'examId': examId,
        'studentId': studentId,
        'maxViolations': maxViolations ?? 2,
        'hasViolationLimit': hasViolationLimit ?? true,
        'allowedPackages': allowedPackages,
      });
      _examActive = true;
    } on MissingPluginException {
      // bukan Android
    } catch (_) {}
  }

  Future<void> stop() async {
    _examActive = false;
    try {
      await _method.invokeMethod('stopExam');
    } on MissingPluginException {
    } catch (_) {}
  }

  Future<void> requestPin() async {
    try {
      await _method.invokeMethod('requestPin');
    } on MissingPluginException {
    } catch (_) {}
  }

  Future<bool> unlockExam(String code) async {
    try {
      final success = await _method.invokeMethod<bool>('unlockExam', {'code': code});
      await refresh();
      return success ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> resetViolations() async {
    try {
      await _method.invokeMethod('resetViolations');
      await refresh();
    } on MissingPluginException {
    } catch (_) {}
  }

  Future<void> openSetting(KioskSetting s) async {
    try {
      await _method.invokeMethod('openSetting', {'name': s.name});
    } on MissingPluginException {
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }
}

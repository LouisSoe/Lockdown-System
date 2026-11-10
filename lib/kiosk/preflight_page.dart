import 'package:flutter/material.dart';

import 'kiosk_controller.dart';

class _Item {
  const _Item(this.key, this.title, this.required, this.setting);
  final String key;
  final String title;
  final bool required;
  final KioskSetting setting;
}

class PreflightPage extends StatelessWidget {
  const PreflightPage({
    super.key,
    required this.kiosk,
    required this.onReady,
    this.buttonText,
  });

  final KioskController kiosk;
  final VoidCallback onReady;
  final String? buttonText;

  static const _items = <_Item>[
    _Item('guard', 'Layanan aksesibilitas "Penjaga Ujian" aktif', true, KioskSetting.guard),
    _Item('overlay', 'Izin tampil di atas aplikasi lain', true, KioskSetting.overlay),
    _Item('battery', 'Optimasi baterai dimatikan untuk aplikasi ini', true, KioskSetting.battery),
    _Item('notif', 'Izin notifikasi', true, KioskSetting.notif),
    _Item('usage', 'Akses penggunaan aplikasi (cadangan deteksi)', false, KioskSetting.usage),
    _Item('home', 'Aplikasi ujian sebagai layar utama', false, KioskSetting.home),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kiosk,
      builder: (context, _) {
        final s = kiosk.status;
        return Scaffold(
          appBar: AppBar(title: const Text('Persiapan Ujian')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final it in _items)
                ListTile(
                  leading: Icon(
                    s.flag(it.key)
                        ? Icons.check_circle
                        : (it.required ? Icons.cancel : Icons.warning_amber),
                    color: s.flag(it.key)
                        ? Colors.green
                        : (it.required ? Colors.red : Colors.orange),
                    size: 28,
                  ),
                  title: Text(
                    it.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    it.required ? 'Wajib' : 'Disarankan',
                    style: TextStyle(
                      color: it.required ? Colors.red.shade700 : Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                  trailing: s.flag(it.key)
                      ? const Icon(Icons.done, color: Colors.green)
                      : FilledButton.tonal(
                          onPressed: () => kiosk.openSetting(it.setting),
                          child: const Text('Atur'),
                        ),
                ),
              const Divider(height: 32),
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pada beberapa merek (Xiaomi, Oppo, Vivo, Samsung) aktifkan juga '
                        '"Mulai otomatis" dan "Tanpa batasan baterai" di pengaturan aplikasi.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: s.prereqOk ? onReady : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  buttonText ?? 'Mulai Ujian',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

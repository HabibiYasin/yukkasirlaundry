import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LaundryLogo {
  static String key(String store) => 'laundry_logo_$store';
  static Future<Uint8List?> load(String store) async {
    final value = (await SharedPreferences.getInstance()).getString(key(store));
    if (value == null) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String store, Uint8List? bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = bytes == null
        ? await prefs.remove(key(store))
        : await prefs.setString(key(store), base64Encode(bytes));
    if (!ok) throw StateError('Logo gagal disimpan.');
  }
}

class LaundryLogoSetting extends StatefulWidget {
  const LaundryLogoSetting({super.key, required this.store});
  final String store;
  @override
  State<LaundryLogoSetting> createState() => _LaundryLogoSettingState();
}

class _LaundryLogoSettingState extends State<LaundryLogoSetting> {
  Uint8List? logo;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      logo = await LaundryLogo.load(widget.store);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change({bool remove = false}) async {
    setState(() => busy = true);
    try {
      Uint8List? bytes;
      if (!remove) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg'],
          withData: true,
        );
        if (picked == null) return;
        final raw = picked.files.single.bytes;
        if (raw == null || raw.length > 5 * 1024 * 1024) {
          throw const FormatException('Pilih gambar PNG/JPG maksimal 5 MB.');
        }
        final codec = await ui.instantiateImageCodec(raw, targetWidth: 512);
        try {
          final frame = await codec.getNextFrame();
          try {
            bytes = (await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
      await LaundryLogo.save(widget.store, bytes);
      if (mounted) setState(() => logo = bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Logo gagal disimpan. Pilih PNG/JPG valid maksimal 5 MB.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Logo pada nota',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Disimpan hanya di perangkat ini, per toko. PNG/JPG, maksimal 5 MB.',
          ),
          if (logo != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Image.memory(
                logo!,
                height: 80,
                width: 100,
                fit: BoxFit.contain,
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => change(),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(logo == null ? 'Tambah logo' : 'Ganti logo'),
              ),
              if (logo != null)
                TextButton(
                  onPressed: busy ? null : () => change(remove: true),
                  child: const Text('Hapus logo'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

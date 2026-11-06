import 'package:flutter/services.dart';

String whatsappPhone(String value) {
  var phone = value.trim().replaceAll(RegExp(r'[\s()+.\-]'), '');
  if (phone.startsWith('00')) phone = phone.substring(2);
  if (phone.startsWith('0')) {
    phone = '62${phone.substring(1)}';
  } else if (phone.startsWith('8')) {
    phone = '62$phone';
  }
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(phone)) {
    throw const FormatException(
      'Nomor HP pelanggan belum diisi atau tidak valid. Perbaiki nomor pelanggan terlebih dahulu.',
    );
  }
  return phone;
}

class WhatsappReceipt {
  static const channel = MethodChannel('yuk_kasir/whatsapp_receipt');

  static Future<void> send({
    required String phone,
    required String text,
    Uint8List? image,
  }) => channel.invokeMethod<void>('sendReceipt', {
    'phone': whatsappPhone(phone),
    'text': text,
    'image': ?image,
  });
}

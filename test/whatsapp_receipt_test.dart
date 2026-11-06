import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/whatsapp_receipt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes local and international customer numbers', () {
    for (final phone in [
      '0812-3456-7890',
      '81234567890',
      '+62 812 3456 7890',
      '006281234567890',
    ]) {
      expect(whatsappPhone(phone), '6281234567890');
    }
    expect(whatsappPhone('+44 7700 900123'), '447700900123');
    for (final phone in [
      '',
      '123',
      '0812abc345678',
      '000',
      '1234567890123456',
    ]) {
      expect(() => whatsappPhone(phone), throwsFormatException);
    }
  });

  test('passes recipient and receipt to Android for both formats', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WhatsappReceipt.channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WhatsappReceipt.channel, null),
    );
    await WhatsappReceipt.send(phone: '081234567890', text: 'Nota\nRp 10.000');
    await WhatsappReceipt.send(
      phone: '081234567890',
      text: 'Nota',
      image: Uint8List.fromList([1, 2, 3]),
    );
    expect(calls[0].method, 'sendReceipt');
    expect(calls[0].arguments, {
      'phone': '6281234567890',
      'text': 'Nota\nRp 10.000',
    });
    expect(calls[1].arguments['phone'], '6281234567890');
    expect(calls[1].arguments['image'], [1, 2, 3]);
    expect(
      () => WhatsappReceipt.send(phone: '', text: 'Nota'),
      throwsFormatException,
    );
    expect(calls, hasLength(2));
  });
}

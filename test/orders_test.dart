import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:printing/src/method_channel.dart';
import 'package:yuk_kasir/laundry_receipt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yuk_kasir/orders.dart';

class TransparentReceiptPrinting extends MethodChannelPrinting {
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    // Transparent paper next to an opaque black text pixel, on two pages.
    yield PdfRaster(2, 1, Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 255]));
    yield PdfRaster(1, 1, Uint8List.fromList([0, 0, 0, 0]));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'video cart and shared receipt agree on total and unpaid balance',
    () async {
      final first = OrderDraftLine(
        id: 'two',
        values: ['Cuci Lipat 2 Jam', 'KG', 0, 2, 7000, 3],
        quantity: 3,
      );
      final second = OrderDraftLine(
        id: 'six',
        values: ['Cuci Lipat 6 Jam', 'KG', 0, 6, 6000, 3],
        quantity: 3,
      );
      expect(first.amount + second.amount, 39000);
      final data = <String, dynamic>{
        'store': {'name': 'Laundry', 'address': 'Depok', 'phone': '081'},
        'number': 'YK-TEST',
        'customer': {'name': 'Konsumen tes', 'phone': '082'},
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 5, 14, 17)),
        'dueAt': Timestamp.fromDate(DateTime(2026, 11, 5, 20, 17)),
        'lines': [
          {
            'name': 'Cuci Lipat 2 Jam',
            'quantity': 3,
            'unit': 'KG',
            'price': 7000,
            'amount': 21000,
            'note': '',
          },
          {
            'name': 'Cuci Lipat 6 Jam',
            'quantity': 3,
            'unit': 'KG',
            'price': 6000,
            'amount': 18000,
            'note': '',
          },
        ],
        'total': 39000,
        'paid': 0,
        'balance': 39000,
        'paymentStatus': 'Belum lunas',
        'status': 'Baru',
        'note': '',
      };
      final text = receiptText(data);
      final pdf = await buildLaundryPdf(data);
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      expect(pdf.length, greaterThan(1000));
      expect(text, contains('Total: Rp 39.000'));
      expect(text, contains('Sisa tagihan: Rp 39.000'));
      expect(text, contains('20:17'));
      expect(text, contains('Belum lunas'));
      final originalPrinting = PrintingPlatform.instance;
      PrintingPlatform.instance = TransparentReceiptPrinting();
      addTearDown(() => PrintingPlatform.instance = originalPrinting);
      final png = await receiptImage(data);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      try {
        expect(image.width, 2);
        expect(image.height, 2);
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        expect(pixels, [
          255, 255, 255, 255, // Transparent paper becomes white.
          0, 0, 0, 255, // Printed content is preserved.
          255, 255, 255, 255, // Second page also has white paper.
          255, 255, 255, 255, // Space beside a narrower page stays white.
        ]);
      } finally {
        image.dispose();
        codec.dispose();
      }
    },
  );
}

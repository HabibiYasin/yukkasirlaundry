import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/monthly_report.dart';

void main() {
  final order = <String, dynamic>{
    'number': 'YK-TEST',
    'customer': {'name': '=SUM(A1)'},
    'createdAt': Timestamp.fromDate(DateTime(2026, 11, 6)),
    'status': 'Baru',
    'paymentStatus': 'DP',
    'total': 50000,
    'paid': 10000,
    'balance': 40000,
  };
  test('Excel exports numeric money and literal customer text with matching totals', () {
    final book = Excel.decodeBytes(
      monthlyReportExcel('Laundry', 'November 2026', [order]),
    );
    final rows = book['Transaksi'].rows;
    expect(rows.length, 2);
    expect(rows[1][2]!.value, isA<TextCellValue>());
    expect(rows[1][2]!.value.toString(), '=SUM(A1)');
    expect(rows[1][5]!.value, IntCellValue(50000));
    expect(book['Ringkasan'].rows[4][1]!.value, IntCellValue(50000));
    final empty = Excel.decodeBytes(
      monthlyReportExcel('Laundry', 'November 2026', []),
    );
    expect(empty['Transaksi'].rows.length, 1);
    expect(empty['Ringkasan'].rows[4][1]!.value, IntCellValue(0));
  });
  test('PDF supports empty and multi-page monthly reports', () async {
    for (final orders in [
      <Map<String, dynamic>>[],
      List.generate(150, (_) => order),
    ]) {
      final bytes = await monthlyReportPdf('Laundry', 'November 2026', orders);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    }
  });
}

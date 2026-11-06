import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'orders.dart' show orderDate, rupiah;

const reportHeaders = [
  'No. nota',
  'Tanggal',
  'Konsumen',
  'Status',
  'Pembayaran',
  'Total (Rp)',
  'Dibayar (Rp)',
  'Sisa (Rp)',
];

List<Object> reportRow(Map<String, dynamic> order) => [
  order['number'] ?? '',
  orderDate(order['createdAt']),
  (order['customer'] as Map?)?['name'] ?? '',
  order['status'] ?? '',
  order['paymentStatus'] ?? '',
  (order['total'] as num?) ?? 0,
  (order['paid'] as num?) ?? 0,
  (order['balance'] as num?) ?? 0,
];

num reportTotal(List<Map<String, dynamic>> orders, String field) =>
    orders.fold<num>(0, (sum, order) => sum + ((order[field] as num?) ?? 0));

Uint8List monthlyReportExcel(
  String store,
  String period,
  List<Map<String, dynamic>> orders,
) {
  final book = Excel.createExcel();
  final summary = book['Ringkasan'];
  book.delete('Sheet1');
  for (final row in <List<Object>>[
    ['Laporan transaksi bulanan'],
    ['Toko', store],
    ['Periode', period],
    ['Jumlah transaksi', orders.length],
    ['Total omzet (Rp)', reportTotal(orders, 'total')],
    ['Dibayar (Rp)', reportTotal(orders, 'paid')],
    ['Sisa tagihan (Rp)', reportTotal(orders, 'balance')],
    [
      'Omzet termasuk transaksi belum lunas. Dibayar dan sisa adalah posisi saat ekspor untuk transaksi periode ini.',
    ],
  ]) {
    summary.appendRow(row.map(_cell).toList());
  }
  summary.setColumnWidth(0, 35);
  summary.setColumnWidth(1, 30);
  final sheet = book['Transaksi'];
  sheet.appendRow(reportHeaders.map(TextCellValue.new).toList());
  for (final order in orders) {
    sheet.appendRow(reportRow(order).map(_cell).toList());
  }
  for (var i = 0; i < reportHeaders.length; i++) {
    sheet.setColumnWidth(i, i == 0 ? 32 : 23);
  }
  return Uint8List.fromList(book.encode()!);
}

CellValue _cell(Object value) => value is num
    ? DoubleCellValue(value.toDouble())
    : TextCellValue(value.toString());

Future<Uint8List> monthlyReportPdf(
  String store,
  String period,
  List<Map<String, dynamic>> orders,
) async {
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 10000,
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Laporan transaksi bulanan',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('$store | $period'),
          ],
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Halaman ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        pw.Text(
          'Total omzet: ${rupiah(reportTotal(orders, 'total'))}',
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${orders.length} transaksi | Dibayar: ${rupiah(reportTotal(orders, 'paid'))} | Sisa: ${rupiah(reportTotal(orders, 'balance'))}',
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Omzet termasuk transaksi belum lunas. Dibayar dan sisa adalah posisi saat ekspor untuk transaksi periode ini.',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 16),
        if (orders.isEmpty)
          pw.Text('Belum ada transaksi pada periode ini.')
        else
          pw.TableHelper.fromTextArray(
            headers: reportHeaders,
            data: orders
                .map(
                  (order) =>
                      reportRow(order)
                          .map((value) => value.toString())
                          .toList(),
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
      ],
    ),
  );
  return document.save();
}

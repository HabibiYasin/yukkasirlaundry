import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'orders.dart' show rupiah, orderDate;

Future<Uint8List> buildLaundryPdf(
  Map<String, dynamic> d, {
  Uint8List? logo,
}) async {
  final pdf = pw.Document();
  const navy = PdfColor.fromInt(0xff0c2c42);
  final store = d['store'] as Map;
  final customer = d['customer'] as Map;
  pw.Widget field(String label, dynamic value, {PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: '${value ?? '-'}',
            style: color == null
                ? null
                : pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${store['name']}',
                    style: pw.TextStyle(
                      fontSize: 30,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text('${store['address']}'),
                  pw.SizedBox(height: 4),
                  pw.Text('Telp: ${store['phone']}'),
                ],
              ),
            ),
            if (logo != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 20),
                child: pw.Image(
                  pw.MemoryImage(logo),
                  width: 110,
                  height: 110,
                  fit: pw.BoxFit.contain,
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Container(height: 5, color: navy),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 18),
          child: pw.Center(
            child: pw.Text(
              'INVOICE LAUNDRY',
              style: pw.TextStyle(
                fontSize: 21,
                color: navy,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
        field('Nomor nota', d['number']),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Tanggal', orderDate(d['createdAt'])),
                  field('Nama pelanggan', customer['name']),
                  field('Estimasi selesai', orderDate(d['dueAt'])),
                ],
              ),
            ),
            pw.SizedBox(width: 18),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Alamat', customer['address']),
                  field('Nomor HP', customer['phone']),
                  field('Status cucian', d['status']),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: [
            'No',
            'Jenis layanan',
            'Jumlah',
            'Harga / unit',
            'Subtotal',
          ],
          data: [
            for (final (i, line) in (d['lines'] as List).indexed)
              [
                '${i + 1}',
                '${line['name']}${(line['note'] ?? '').toString().isEmpty ? '' : '\n${line['note']}'}',
                '${line['quantity']} ${line['unit']}',
                rupiah(line['price']),
                rupiah(line['amount']),
              ],
          ],
          headerDecoration: const pw.BoxDecoration(color: navy),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.all(10),
          columnWidths: {
            0: const pw.FixedColumnWidth(28),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(),
            3: const pw.FlexColumnWidth(1.3),
            4: const pw.FlexColumnWidth(1.3),
          },
        ),
        pw.SizedBox(height: 18),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total biaya: ${rupiah(d['total'])}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Detail pembayaran',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        field(
          'Metode pembayaran awal',
          (d['paymentMethod'] ?? '').toString().isEmpty
              ? '-'
              : d['paymentMethod'],
        ),
        field(
          'Status pembayaran',
          d['paymentStatus'],
          color: '${d['paymentStatus']}'.trim().toLowerCase() == 'lunas'
              ? PdfColors.green800
              : PdfColors.red800,
        ),
        field('Dibayar', rupiah(d['paid'])),
        field('Sisa tagihan', rupiah(d['balance'])),
        if ((d['note'] ?? '').toString().isNotEmpty)
          field('Keterangan', d['note']),
        pw.SizedBox(height: 12),
        pw.Text(
          'Syarat dan ketentuan:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
        pw.SizedBox(height: 6),
        for (final (index, term) in const [
          'Pengambilan barang harap disertai nota',
          'Barang yang tidak diambil selama 1 bulan, hilang / rusak tidak diganti',
          'Disampaikan Max 1 × 24 jam dan mengisi form Komplain',
          'Klaim luntur tidak dipisah diluar tanggungan',
          'Kerusakan dan kehilangan pakaian akan diselesaikan dalam waktu paling lama 1 minggu sejak menandatangani komplain',
        ].indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 14,
                  child: pw.Text(
                    '${index + 1}.',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(term, style: const pw.TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 20),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          color: navy,
          child: pw.Text(
            'Terima kasih telah menggunakan layanan kami.\nHarap simpan nota ini sebagai bukti transaksi.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 11),
          ),
        ),
      ],
    ),
  );
  return pdf.save();
}

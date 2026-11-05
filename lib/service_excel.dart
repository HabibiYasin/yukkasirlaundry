import 'dart:typed_data';

import 'package:excel/excel.dart';

const serviceColumns = [
  'Nama',
  'Satuan',
  'Durasi Hari',
  'Durasi Jam',
  'Harga',
  'Min. Order Reguler',
  'Min. Order Deposit',
  'Tags',
  'Label (Rp)',
  'Sortir (Rp)',
  'Cleaning (Rp)',
  'Spotting (Rp)',
  'Detailing (Rp)',
  'Cuci (Rp)',
  'Kering (Rp)',
  'Setrika (Rp)',
  'Extra Setrika (Rp)',
  'Pengemasan (Rp)',
  'Lipat (Rp)',
];
bool numericColumn(int i) => ![0, 1, 7].contains(i);
List<dynamic> validateService(List<dynamic> row, int number) {
  if (row.length != 19) {
    throw FormatException('Baris $number harus memiliki 19 kolom.');
  }
  return List.generate(19, (i) {
    final s = row[i]?.toString().trim() ?? '';
    if (!numericColumn(i)) {
      if (i < 2 && s.isEmpty) {
        throw FormatException(
          'Baris $number: ${serviceColumns[i]} wajib diisi.',
        );
      }
      return s;
    }
    final n = num.tryParse(s.isEmpty ? '0' : s);
    if (n == null ||
        !n.isFinite ||
        n < 0 ||
        ((i == 2 || i == 3) && n % 1 != 0)) {
      throw FormatException(
        'Baris $number: ${serviceColumns[i]} harus angka positif (durasi bilangan bulat).',
      );
    }
    return n;
  });
}

List<List<dynamic>> decodeServices(List<int> bytes) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) throw const FormatException('File kosong.');
  final rows = book.tables.values.first.rows;
  if (rows.isEmpty) throw const FormatException('File kosong.');
  final header = rows.first
      .map((c) => c?.value.toString().trim() ?? '')
      .toList();
  if (header.length != 19 ||
      List.generate(
        19,
        (i) => header[i] == serviceColumns[i],
      ).contains(false)) {
    throw const FormatException('Header tidak sesuai template 19 kolom.');
  }
  final result = <List<dynamic>>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i].map((c) => c?.value.toString() ?? '').toList();
    if (row.every((c) => c.trim().isEmpty)) continue;
    while (row.length < 19) {
      row.add('');
    }
    result.add(validateService(row, i + 1));
  }
  if (result.isEmpty) {
    throw const FormatException('Tidak ada layanan untuk diimpor.');
  }
  return result;
}

Uint8List encodeServices(List<List<dynamic>> rows) {
  final book = Excel.createExcel();
  final sheet = book['Layanan'];
  book.delete('Sheet1');
  sheet.appendRow(serviceColumns.map(TextCellValue.new).toList());
  for (final row in rows) {
    sheet.appendRow(
      List.generate(
        19,
        (i) => numericColumn(i)
            ? DoubleCellValue((row[i] as num).toDouble())
            : TextCellValue(row[i].toString()),
      ),
    );
  }
  return Uint8List.fromList(book.encode()!);
}

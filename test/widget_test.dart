import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/service_excel.dart';

void main() {
  test('19-column workbook round trip preserves values', () {
    final row = List<dynamic>.generate(
      19,
      (i) => i == 0
          ? 'Cuci reguler'
          : i == 1
          ? 'KG'
          : i == 7
          ? 'reguler'
          : i * 100,
    );
    expect(decodeServices(encodeServices([row])), [row]);
  });
  test('reject negative and invalid price', () {
    final row = List<dynamic>.generate(
      19,
      (i) => i == 0
          ? 'Cuci'
          : i == 1
          ? 'KG'
          : i == 7
          ? ''
          : 0,
    );
    row[4] = -1;
    expect(() => validateService(row, 2), throwsFormatException);
    row[4] = 'abc';
    expect(() => validateService(row, 2), throwsFormatException);
  });
  test('provided workbook imports all rows', () {
    final f = File('test/fixtures/services.xlsx');
    final rows = decodeServices(f.readAsBytesSync());
    expect(rows.length, greaterThan(100));
    expect(rows.first[0], 'Sprei 4 btl 2 glg');
    expect(rows.first[4], 38500);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yuk_kasir/orders.dart';

void main() {
  test('video cart and shared receipt agree on total and unpaid balance', () {
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
    final text = receiptText({
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
    });
    expect(text, contains('Total: Rp 39.000'));
    expect(text, contains('Sisa tagihan: Rp 39.000'));
    expect(text, contains('20:17'));
    expect(text, contains('Belum lunas'));
  });
}

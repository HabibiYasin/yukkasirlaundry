import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/store_summary.dart';
import 'package:yuk_kasir/transaction_recap.dart';

void main() {
  test('selected period does not change the clock used for deadlines', () {
    final result = summarizeStore(
      [
        {
          'createdAt': Timestamp.fromDate(DateTime(2026, 10, 30)),
          'dueAt': Timestamp.fromDate(DateTime(2026, 11, 2)),
          'status': 'Baru',
        },
        {
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
          'status': 'Baru',
        },
      ],
      [
        {
          'at': Timestamp.fromDate(DateTime(2026, 10, 31)),
          'type': 'payment',
          'amount': 7000,
        },
        {
          'at': Timestamp.fromDate(DateTime(2026, 11, 1)),
          'type': 'payment',
          'amount': 9000,
        },
      ],
      DateTime(2026, 11, 6),
      month: DateTime(2026, 10),
    );
    expect(result.transactions, 1);
    expect(result.overdue, 1);
    expect(result.income, 7000);
  });

  test('turnover includes unpaid amounts and handles empty months', () {
    expect(
      totalTurnover([
        {'total': 50000, 'paid': 10000},
        {'total': 25000, 'paid': 0},
      ]),
      75000,
    );
    expect(totalTurnover([]), 0);
    expect(
      inMonth(Timestamp.fromDate(DateTime(2027, 1, 1)), DateTime(2026, 12)),
      isFalse,
    );
  });

  testWidgets('month selector applies month and year, cancel preserves value', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthSelector(
            value: DateTime(2026, 11),
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('November 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oktober').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tampilkan'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2025, 10));
    selected = null;
    await tester.tap(find.text('November 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}

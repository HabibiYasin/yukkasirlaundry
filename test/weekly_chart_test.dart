import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/weekly_chart.dart';

void main() {
  test('week spans month/year boundaries and cash follows payment date', () {
    final start = weekStart(DateTime(2027, 1, 1));
    expect(start, DateTime(2026, 12, 28));
    final totals = weeklyTotals(
      [
        {'createdAt': Timestamp.fromDate(start)},
        {'createdAt': Timestamp.fromDate(DateTime(2027, 1, 3, 23, 59))},
        {'createdAt': Timestamp.fromDate(DateTime(2027, 1, 4))},
      ],
      [
        {'type': 'created', 'at': Timestamp.fromDate(start), 'paid': 10000},
        {'type': 'payment', 'at': Timestamp.fromDate(start), 'amount': 5000},
        {
          'type': 'payment',
          'at': Timestamp.fromDate(DateTime(2027, 1, 4)),
          'amount': 999,
        },
      ],
      start,
    );
    expect(totals.first.transactions, 1);
    expect(totals.last.transactions, 1);
    expect(totals.first.income, 15000);
    expect(totals[1].income, 0);
  });
  testWidgets(
    'empty weekly charts fit phone width and support week navigation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: WeeklyCharts(
                  orders: const [],
                  events: const [],
                  now: DateTime(2026, 11, 6),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2/11/2026 – 8/11/2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Minggu sebelumnya'));
      await tester.pump();
      expect(find.text('26/10/2026 – 1/11/2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

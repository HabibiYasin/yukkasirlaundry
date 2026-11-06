import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/store_summary.dart';

void main() {
  test(
    'daily summary excludes yesterday and tomorrow, includes payments today',
    () {
      final now = DateTime(2026, 11, 6, 14);
      final result = summarizeStore(
        [
          for (final day in [5, 6, 7])
            {
              'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
              'dueAt': Timestamp.fromDate(DateTime(2026, 11, day, 12)),
              'status': 'Baru',
            },
        ],
        [
          for (final day in [5, 6, 7])
            {
              'at': Timestamp.fromDate(DateTime(2026, 11, day)),
              'type': 'payment',
              'amount': 15000,
            },
          {'at': Timestamp.fromDate(now), 'type': 'created', 'paid': 5000},
        ],
        now,
        daily: true,
      );
      expect(result.transactions, 1);
      expect(result.pending, 1);
      expect(result.overdue, 1);
      expect(result.income, 20000);
      expect(summaryDayLabel(now), 'Jumat, 06 November 2026');
    },
  );

  testWidgets('compact metrics fit narrow screens and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: CompactSummaryCard(
                  title: 'Transaksi Hari Ini',
                  subtitle: 'Jumat, 06 November 2026',
                  summary: (
                    transactions: 100,
                    pending: 20,
                    overdue: 3,
                    income: 1000000000,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Transaksi Hari Ini'), findsOneWidget);
    expect(find.text('Belum dikerjakan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

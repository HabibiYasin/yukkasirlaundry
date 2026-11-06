import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuk_kasir/store_summary.dart';

void main() {
  test(
    'monthly summary uses payment dates and only unfinished overdue orders',
    () {
      final now = DateTime(2026, 11, 6, 12);
      Map<String, dynamic> order(
        String status,
        DateTime created,
        DateTime due,
      ) => {
        'status': status,
        'createdAt': Timestamp.fromDate(created),
        'dueAt': Timestamp.fromDate(due),
      };
      final result = summarizeStore(
        [
          order(
            'Baru',
            DateTime(2026, 11, 1),
            now.subtract(const Duration(hours: 1)),
          ),
          order(
            'Diproses',
            DateTime(2026, 11, 1),
            now.subtract(const Duration(hours: 1)),
          ),
          order(
            'Siap diambil',
            DateTime(2026, 11, 1),
            now.subtract(const Duration(days: 1)),
          ),
          order(
            'Diambil',
            DateTime(2026, 11, 1),
            now.subtract(const Duration(days: 1)),
          ),
          order('Baru', DateTime(2026, 11, 1), now),
          order('Baru', DateTime(2026, 10, 31), now),
          order('Baru', DateTime(2026, 12, 1), now),
        ],
        [
          {
            'type': 'created',
            'at': Timestamp.fromDate(DateTime(2026, 11, 1)),
            'paid': 10000,
          },
          {'type': 'payment', 'at': Timestamp.fromDate(now), 'amount': 15000},
          {
            'type': 'payment',
            'at': Timestamp.fromDate(DateTime(2026, 10, 31)),
            'amount': 999,
          },
          {
            'type': 'payment',
            'at': Timestamp.fromDate(DateTime(2026, 12, 1)),
            'amount': 999,
          },
          {'type': 'status', 'at': Timestamp.fromDate(now)},
        ],
        now,
      );
      expect(result.transactions, 5);
      expect(result.pending, 2);
      expect(result.overdue, 2);
      expect(result.income, 25000);
      expect(summarizeStore([], [], now).income, 0);
    },
  );
}

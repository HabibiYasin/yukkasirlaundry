import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'orders.dart' show rupiah;

DateTime weekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);

List<({DateTime date, int transactions, num income})> weeklyTotals(
  Iterable<Map<String, dynamic>> orders,
  Iterable<Map<String, dynamic>> events,
  DateTime start,
) {
  final counts = List.filled(7, 0);
  final income = List<num>.filled(7, 0);
  int dayIndex(dynamic stamp) {
    if (stamp is! Timestamp) return -1;
    final d = stamp.toDate();
    return DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
  }

  for (final order in orders) {
    final i = dayIndex(order['createdAt']);
    if (i >= 0 && i < 7) counts[i]++;
  }
  for (final event in events) {
    final i = dayIndex(event['at']);
    if (i < 0 || i >= 7) continue;
    if (event['type'] == 'created') income[i] += (event['paid'] as num?) ?? 0;
    if (event['type'] == 'payment') income[i] += (event['amount'] as num?) ?? 0;
  }
  return List.generate(
    7,
    (i) => (
      date: DateTime(start.year, start.month, start.day + i),
      transactions: counts[i],
      income: income[i],
    ),
  );
}

class WeeklyCharts extends StatefulWidget {
  const WeeklyCharts({
    super.key,
    required this.orders,
    required this.events,
    required this.now,
  });
  final List<Map<String, dynamic>> orders, events;
  final DateTime now;
  @override
  State<WeeklyCharts> createState() => _WeeklyChartsState();
}

class _WeeklyChartsState extends State<WeeklyCharts> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final current = weekStart(widget.now);
    final start = DateTime(
      current.year,
      current.month,
      current.day + offset * 7,
    );
    final days = weeklyTotals(widget.orders, widget.events, start);
    String date(DateTime d) => '${d.day}/${d.month}/${d.year}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diagram mingguan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Minggu sebelumnya',
                  onPressed: () => setState(() => offset--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${date(start)} – ${date(days.last.date)}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Minggu berikutnya',
                  onPressed: offset < 0 ? () => setState(() => offset++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            chart(
              context,
              'Transaksi per hari',
              days.map((d) => d.transactions).toList(),
              money: false,
            ),
            const SizedBox(height: 16),
            chart(
              context,
              'Uang masuk per hari',
              days.map((d) => d.income).toList(),
              money: true,
            ),
            const SizedBox(height: 8),
            const Text(
              'Uang masuk mengikuti tanggal pembayaran, termasuk pelunasan pesanan lama.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget chart(
    BuildContext context,
    String title,
    List<num> values, {
    required bool money,
  }) {
    final max = values.fold<num>(0, (a, b) => a > b ? a : b);
    final total = values.fold<num>(0, (a, b) => a + b);
    const labels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    String amount(num n) => money ? rupiah(n) : '$n transaksi';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Total: ${amount(total)}'),
        const SizedBox(height: 8),
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(labels[i], style: const TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Semantics(
                    label: '${labels[i]}: ${amount(values[i])}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: max == 0 ? 0 : values[i] / max,
                        minHeight: 12,
                        color: money
                            ? Colors.teal
                            : Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: money ? 110 : 42,
                  child: Text(
                    money ? rupiah(values[i]) : '${values[i]}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

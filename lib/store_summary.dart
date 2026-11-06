import 'weekly_chart.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'orders.dart' show rupiah;
import 'transaction_recap.dart';

bool inMonth(dynamic value, DateTime now) {
  if (value is! Timestamp) return false;
  final date = value.toDate();
  return !date.isBefore(DateTime(now.year, now.month)) &&
      date.isBefore(DateTime(now.year, now.month + 1));
}

({int transactions, int pending, int overdue, num income}) summarizeStore(
  Iterable<Map<String, dynamic>> orders,
  Iterable<Map<String, dynamic>> events,
  DateTime now, {
  DateTime? month,
  bool daily = false,
}) {
  final period = month ?? now;
  bool included(dynamic value) {
    if (!daily) return inMonth(value, period);
    if (value is! Timestamp) return false;
    final date = value.toDate();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  int transactions = 0, pending = 0, overdue = 0;
  num income = 0;
  for (final order in orders) {
    if (!included(order['createdAt'])) continue;
    transactions++;
    if (order['status'] == 'Baru') pending++;
    final due = order['dueAt'];
    if (['Baru', 'Diproses'].contains(order['status']) &&
        due is Timestamp &&
        due.toDate().isBefore(now)) {
      overdue++;
    }
  }
  for (final event in events) {
    if (!included(event['at'])) continue;
    if (event['type'] == 'created') income += (event['paid'] as num?) ?? 0;
    if (event['type'] == 'payment') income += (event['amount'] as num?) ?? 0;
  }
  return (
    transactions: transactions,
    pending: pending,
    overdue: overdue,
    income: income,
  );
}

class StoreSummary extends StatefulWidget {
  const StoreSummary({
    super.key,
    required this.store,
    this.weekly = false,
    this.month,
  });
  final String store;
  final bool weekly;
  final DateTime? month;
  @override
  State<StoreSummary> createState() => _StoreSummaryState();
}

class _StoreSummaryState extends State<StoreSummary> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
  final payments =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final events = <String, List<Map<String, dynamic>>>{};
  List<Map<String, dynamic>> orders = [];
  final failures = <String, Object>{};
  bool loaded = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // Also refresh overdue counts and month boundaries without a database write.
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    subscription = items(widget.store, 'orders').snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          loaded = true;
          failures.remove('orders');
          orders = snapshot.docs.map((d) => d.data()).toList();
          final ids = snapshot.docs.map((d) => d.id).toSet();
          for (final id in payments.keys.toList()) {
            if (!ids.contains(id)) {
              payments.remove(id)?.cancel();
              events.remove(id);
              failures.remove(id);
            }
          }
          // Per-order queries preserve the existing store membership rules and
          // include payments this month for orders from previous months.
          for (final doc in snapshot.docs) {
            payments.putIfAbsent(
              doc.id,
              () => doc.reference
                  .collection('events')
                  .snapshots()
                  .listen(
                    (s) {
                      if (!mounted) return;
                      setState(() {
                        failures.remove(doc.id);
                        events[doc.id] = s.docs.map((e) => e.data()).toList();
                      });
                    },
                    onError: (Object e) {
                      if (mounted) setState(() => failures[doc.id] = e);
                    },
                  ),
            );
          }
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => failures['orders'] = e);
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    subscription?.cancel();
    for (final sub in payments.values) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failures.isNotEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Ringkasan gagal dimuat. Periksa koneksi lalu buka kembali halaman ini.',
          ),
        ),
      );
    }
    if (!loaded || events.length < payments.length) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    final paymentEvents = events.values.expand((e) => e).toList();
    final daily = summarizeStore(orders, paymentEvents, now, daily: true);
    if (widget.weekly) {
      return Column(
        children: [
          WeeklyCharts(orders: orders, events: paymentEvents, now: now),
          CompactSummaryCard(
            title: 'Ringkasan ${monthLabel(widget.month ?? now)}',
            summary: summarizeStore(
              orders,
              paymentEvents,
              now,
              month: widget.month,
            ),
          ),
        ],
      );
    }
    return CompactSummaryCard(
      title: 'Transaksi Hari Ini',
      subtitle: summaryDayLabel(now),
      summary: daily,
    );
  }
}

String summaryDayLabel(DateTime date) {
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  return '${days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} ${monthNames[date.month - 1]} ${date.year}';
}

typedef StoreTotals = ({
  int transactions,
  int pending,
  int overdue,
  num income,
});

class CompactSummaryCard extends StatelessWidget {
  const CompactSummaryCard({
    super.key,
    required this.title,
    required this.summary,
    this.subtitle,
    this.selector,
  });
  final String title;
  final String? subtitle;
  final Widget? selector;
  final StoreTotals summary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              ?selector,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: metric(context, '${summary.transactions}', 'Transaksi'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: metric(context, rupiah(summary.income), 'Uang masuk'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: metric(
                  context,
                  '${summary.overdue}',
                  'Lewat deadline',
                  alert: summary.overdue > 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: metric(
                  context,
                  '${summary.pending}',
                  'Belum dikerjakan',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget metric(
    BuildContext context,
    String value,
    String label, {
    bool alert = false,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: alert ? Theme.of(context).colorScheme.error : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

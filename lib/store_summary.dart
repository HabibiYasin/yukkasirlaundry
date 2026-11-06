import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'orders.dart' show rupiah;

bool inMonth(dynamic value, DateTime now) {
  if (value is! Timestamp) return false;
  final date = value.toDate();
  return !date.isBefore(DateTime(now.year, now.month)) &&
      date.isBefore(DateTime(now.year, now.month + 1));
}

({int transactions, int pending, int overdue, num income}) summarizeStore(
  Iterable<Map<String, dynamic>> orders,
  Iterable<Map<String, dynamic>> events,
  DateTime now,
) {
  int transactions = 0, pending = 0, overdue = 0;
  num income = 0;
  for (final order in orders) {
    if (!inMonth(order['createdAt'], now)) continue;
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
    if (!inMonth(event['at'], now)) continue;
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
  const StoreSummary({super.key, required this.store});
  final String store;
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
    final summary = summarizeStore(
      orders,
      events.values.expand((e) => e),
      DateTime.now(),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bulan ini', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Transaksi'),
              trailing: Text('${summary.transactions}'),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Uang masuk'),
              subtitle: Text(rupiah(summary.income)),
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_empty),
              title: const Text('Belum dikerjakan'),
              trailing: Text('${summary.pending}'),
            ),
            ListTile(
              leading: const Icon(Icons.event_busy),
              title: const Text('Lewat deadline'),
              trailing: Text('${summary.overdue}'),
            ),
            const Text(
              'Jumlah pesanan berdasarkan tanggal dibuat bulan ini. Uang masuk berdasarkan tanggal pembayaran. Deadline mengikuti tanggal dan jam selesai pesanan.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

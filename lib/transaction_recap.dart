import 'store_summary.dart';

import 'package:share_plus/share_plus.dart';

import 'monthly_report.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'orders.dart';

const monthNames = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
bool sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;
String monthLabel(DateTime value) =>
    '${monthNames[value.month - 1]} ${value.year}';
num totalTurnover(Iterable<Map<String, dynamic>> orders) => orders.fold<num>(
  0,
  (total, order) => total + ((order['total'] as num?) ?? 0),
);

class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.calendar_month, size: 18),
    label: Text(monthLabel(value)),
    onPressed: () async {
      var month = value.month;
      var year = value.year;
      final selected = await showDialog<DateTime>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Pilih bulan dan tahun'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Bulan'),
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(monthNames[i]),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) update(() => month = v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: year,
                  decoration: const InputDecoration(labelText: 'Tahun'),
                  items: List.generate(
                    DateTime.now().year + 2 - 2000,
                    (i) => DropdownMenuItem(
                      value: 2000 + i,
                      child: Text('${2000 + i}'),
                    ),
                  ).reversed.toList(),
                  onChanged: (v) {
                    if (v != null) update(() => year = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, DateTime(year, month)),
                child: const Text('Tampilkan'),
              ),
            ],
          ),
        ),
      );
      if (selected != null && context.mounted) onChanged(selected);
    },
  );
}

class TransactionRecapPage extends StatefulWidget {
  const TransactionRecapPage({
    super.key,
    required this.store,
    this.embedded = false,
  });
  final String store;
  final bool embedded;
  @override
  State<TransactionRecapPage> createState() => _TransactionRecapState();
}

class _TransactionRecapState extends State<TransactionRecapPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  late Stream<QuerySnapshot<Map<String, dynamic>>> transactions;
  bool exporting = false;

  Future<void> exportReport(
    String format,
    List<Map<String, dynamic>> orders,
  ) async {
    final period = monthLabel(month);
    final filename =
        'rekap_${widget.store}_${month.year}-${month.month.toString().padLeft(2, '0')}.$format';
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => exporting = true);
    try {
      final store = await db.collection('stores').doc(widget.store).get();
      final name = store.data()?['name']?.toString() ?? 'Toko';
      final bytes = format == 'xlsx'
          ? monthlyReportExcel(name, period, orders)
          : await monthlyReportPdf(name, period, orders);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          title: 'Laporan $period',
          files: [
            XFile.fromData(
              bytes,
              mimeType: format == 'xlsx'
                  ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                  : 'application/pdf',
            ),
          ],
          fileNameOverrides: [filename],
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekspor gagal: ${errorText(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    loadMonth();
  }

  void loadMonth() {
    transactions = items(widget.store, 'orders')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(month))
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(DateTime(month.year, month.month + 1)),
        )
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(title: const Text('Rekap transaksi')),
    body: Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MonthSelector(
              value: month,
              onChanged: (value) => setState(() {
                month = value;
                loadMonth();
              }),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey(month),
            stream: transactions,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Rekap transaksi gagal dimuat.'),
                      TextButton(
                        onPressed: () => setState(loadMonth),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              final turnover = totalTurnover(docs.map((d) => d.data()));
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StoreSummary(
                          key: ValueKey(widget.store),
                          store: widget.store,
                          weekly: true,
                          month: month,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Transaksi bulanan',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total omzet'),
                                  const SizedBox(height: 8),
                                  Text(
                                    rupiah(turnover),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium,
                                  ),
                                  Text(monthLabel(month)),
                                  const SizedBox(height: 8),
                                  PopupMenuButton<String>(
                                    enabled: !exporting,
                                    tooltip: 'Ekspor laporan bulanan',
                                    onSelected: (format) => exportReport(
                                      format,
                                      docs.map((d) => d.data()).toList(),
                                    ),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'xlsx',
                                        child: Text('Excel (.xlsx)'),
                                      ),
                                      PopupMenuItem(
                                        value: 'pdf',
                                        child: Text('PDF (.pdf)'),
                                      ),
                                    ],
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.file_download_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            exporting
                                                ? 'Menyiapkan laporan...'
                                                : 'Ekspor laporan',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Total nilai transaksi, termasuk yang belum lunas.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${docs.length} transaksi',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (docs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('Belum ada transaksi pada bulan ini.'),
                          ),
                      ],
                    );
                  }
                  final doc = docs[index - 1];
                  final order = doc.data();
                  return Card(
                    child: ListTile(
                      title: Text('${order['customer']['name']}'),
                      subtitle: Text(
                        '${order['number']}\n${orderDate(order['createdAt'])}\n${order['status']} • ${order['paymentStatus']}',
                      ),
                      trailing: Text(rupiah(order['total'])),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderDetailPage(store: widget.store, id: doc.id),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

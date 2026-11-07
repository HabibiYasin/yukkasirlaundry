import 'laundry_logo.dart';
import 'laundry_receipt.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

import 'data.dart';
import 'whatsapp_receipt.dart';
import 'screens.dart' show Records, form, message, confirm;

String rupiah(num n) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
).format(n);
String orderDate(dynamic value) => value is Timestamp
    ? DateFormat('dd/MM/yyyy HH:mm').format(value.toDate())
    : '-';

class OrderDraftLine {
  OrderDraftLine({
    required this.id,
    required this.values,
    required this.quantity,
    this.note = '',
  });
  final String id;
  final List<dynamic> values;
  final double quantity;
  final String note;
  int get amount => (quantity * (values[4] as num)).round();
  Map<String, dynamic> get payload => {
    'serviceId': id,
    'quantity': quantity,
    'expectedPrice': values[4],
    'note': note,
  };
}

class CreateOrderPage extends StatefulWidget {
  const CreateOrderPage({super.key, required this.store});
  final String store;
  @override
  State<CreateOrderPage> createState() => _CreateOrderState();
}

class _CreateOrderState extends State<CreateOrderPage> {
  int step = 0;
  String search = '', paymentType = 'pickup', method = 'Tunai';
  QueryDocumentSnapshot<Map<String, dynamic>>? customer;
  final lines = <OrderDraftLine>[];
  final note = TextEditingController(), deposit = TextEditingController();
  late final String requestId = items(widget.store, 'orders').doc().id;
  bool busy = false;
  int get total => lines.fold(0, (subtotal, l) => subtotal + l.amount);
  @override
  void dispose() {
    note.dispose();
    deposit.dispose();
    super.dispose();
  }

  void go(int n) => setState(() {
    step = n;
    search = '';
  });
  Future<void> addCustomer() async {
    final v = await form(
      context,
      'Tambah konsumen',
      {'Nama': '', 'Nomor HP': '', 'Alamat': ''},
      fromContacts: true,
      requiredFields: {'Nama', 'Nomor HP'},
    );
    if (v == null) return;
    try {
      await items(widget.store, 'customers').add({
        'name': v['Nama'],
        'phone': v['Nomor HP'],
        'address': v['Alamat'],
      });
    } catch (e) {
      if (mounted) message(context, errorText(e));
    }
  }

  Future<void> lineDialog(String id, List<dynamic> values, {int? index}) async {
    if (index == null && lines.length >= maxOrderLines) {
      message(
        context,
        'Maksimal $maxOrderLines layanan per transaksi. Buat transaksi berikutnya untuk layanan tambahan.',
      );
      return;
    }
    final old = index == null ? null : lines[index];
    final v = await form(
      context,
      values[0].toString(),
      {
        'Kuantitas (${values[1]})':
            (old?.quantity ??
                    ((values[5] as num) > 0
                        ? (values[5] as num).toDouble()
                        : 1))
                .toString(),
        'Catatan': old?.note ?? '',
      },
      requiredFields: {'Kuantitas (${values[1]})'},
      numeric: {'Kuantitas (${values[1]})'},
    );
    if (v == null) return;
    final qty = double.parse(v['Kuantitas (${values[1]})']!);
    if (!qty.isFinite ||
        qty <= 0 ||
        qty < (values[5] as num) ||
        qty > 100000 ||
        (qty * 100 - (qty * 100).round()).abs() > 0.00001) {
      if (mounted) {
        message(
          context,
          'Isi kuantitas minimal ${values[5]} ${values[1]}, lebih dari 0, maksimal 2 desimal.',
        );
      }
      return;
    }
    setState(() {
      final l = OrderDraftLine(
        id: id,
        values: values,
        quantity: qty,
        note: v['Catatan']!,
      );
      if (index == null) {
        lines.add(l);
      } else {
        lines[index] = l;
      }
    });
  }

  Future<void> save() async {
    final paid = paymentType == 'paid'
        ? total
        : paymentType == 'pickup'
        ? 0
        : int.tryParse(deposit.text.trim());
    if (paid == null ||
        (paymentType == 'deposit' && (paid <= 0 || paid >= total))) {
      message(
        context,
        'DP harus angka rupiah bulat, lebih dari 0 dan kurang dari total.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      final result = await call('createOrder', {
        'storeId': widget.store,
        'requestId': requestId,
        'customerId': customer!.id,
        'lines': lines.map((l) => l.payload).toList(),
        'note': note.text,
        'paymentType': paymentType,
        'paid': paid,
        'paymentMethod': method,
      });
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailPage(
              store: widget.store,
              id: result['id'],
              created: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) message(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          ['Pilih konsumen', 'Pilih layanan', 'Keranjang', 'Pembayaran'][step],
        ),
        leading: IconButton(
          onPressed: busy
              ? null
              : () async {
                  if (step > 0) {
                    go(step - 1);
                  } else if (lines.isEmpty ||
                      await confirm(
                        c,
                        'Batalkan transaksi?',
                        'Keranjang yang belum disimpan akan hilang.',
                      )) {
                    if (c.mounted) Navigator.pop(c);
                  }
                },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (step + 1) / 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              'Langkah ${step + 1} dari 4${customer == null ? '' : ' • ${customer!.data()['name']}'}',
            ),
          ),
          Expanded(
            child: switch (step) {
              0 => customers(c),
              1 => services(c),
              2 => cart(c),
              _ => payment(c),
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${lines.length} layanan\n${rupiah(total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton(
                onPressed: busy || step == 0 || lines.isEmpty
                    ? null
                    : step == 3
                    ? save
                    : () => go(step + 1),
                child: Text(
                  busy
                      ? 'Menyimpan…'
                      : step == 1
                      ? 'Keranjang'
                      : step == 2
                      ? 'Pembayaran'
                      : 'Selesaikan',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget customers(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Cari nama / nomor HP',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => search = v.toLowerCase()),
        ),
      ),
      Expanded(
        child: Records(
          query: items(widget.store, 'customers'),
          empty: 'Belum ada konsumen.',
          builder: (docs) {
            final found = docs
                .where(
                  (d) => '${d.data()['name']} ${d.data()['phone']}'
                      .toLowerCase()
                      .contains(search),
                )
                .toList();
            return ListView(
              children: [
                if (found.isEmpty)
                  const ListTile(title: Text('Konsumen tidak ditemukan.')),
                for (final d in found)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(d.data()['name']),
                      subtitle: Text(d.data()['phone']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        customer = d;
                        go(1);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      TextButton.icon(
        onPressed: addCustomer,
        icon: const Icon(Icons.add),
        label: const Text('Tambah konsumen baru'),
      ),
    ],
  );
  Widget services(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Cari nama layanan / satuan',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => search = v.toLowerCase()),
        ),
      ),
      Expanded(
        child: Records(
          query: items(widget.store, 'services'),
          empty: 'Tambahkan layanan melalui Pengaturan > Toko terlebih dahulu.',
          builder: (docs) => ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final d in docs)
                if ('${d.data()['values'][0]} ${d.data()['values'][1]}'
                    .toLowerCase()
                    .contains(search))
                  Card(
                    child: ListTile(
                      title: Text(d.data()['values'][0]),
                      subtitle: Text(
                        '${rupiah(d.data()['values'][4])} / ${d.data()['values'][1]}\n${d.data()['values'][2]} hari ${d.data()['values'][3]} jam • Min. ${d.data()['values'][5]}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => lineDialog(
                        d.id,
                        List<dynamic>.from(d.data()['values']),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget cart(BuildContext c) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Daftar pesanan',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < lines.length; i++)
        Card(
          child: ListTile(
            title: Text(lines[i].values[0]),
            subtitle: Text(
              '${lines[i].quantity} ${lines[i].values[1]} × ${rupiah(lines[i].values[4])}\n${rupiah(lines[i].amount)}${lines[i].note.isEmpty ? '' : '\n${lines[i].note}'}',
            ),
            onTap: () => lineDialog(lines[i].id, lines[i].values, index: i),
            trailing: IconButton(
              tooltip: 'Hapus layanan',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => lines.removeAt(i)),
            ),
          ),
        ),
      if (lines.isEmpty) const Text('Keranjang kosong.'),
      TextButton.icon(
        onPressed: () => go(1),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Tambah layanan lainnya'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: note,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Keterangan transaksi'),
      ),
      const SizedBox(height: 16),
      const Text(
        'Estimasi selesai mengikuti durasi layanan terlama. Harga dan minimum order diperiksa kembali saat disimpan.',
      ),
      const SizedBox(height: 12),
      Text(
        'Total tagihan: ${rupiah(total)}',
        style: Theme.of(c).textTheme.titleLarge,
      ),
    ],
  );
  Widget payment(BuildContext c) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      DropdownButtonFormField<String>(
        initialValue: paymentType,
        decoration: const InputDecoration(labelText: 'Tipe pembayaran'),
        items: const [
          DropdownMenuItem(value: 'paid', child: Text('Lunas saat ini')),
          DropdownMenuItem(value: 'deposit', child: Text('DP (Down Payment)')),
          DropdownMenuItem(
            value: 'pickup',
            child: Text('Bayar saat pengambilan'),
          ),
        ],
        onChanged: busy ? null : (v) => setState(() => paymentType = v!),
      ),
      const SizedBox(height: 20),
      if (paymentType == 'deposit')
        TextField(
          controller: deposit,
          enabled: !busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nominal DP (Rp)',
            helperText: 'Masukkan angka tanpa titik atau koma',
          ),
        ),
      if (paymentType != 'pickup')
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Metode pembayaran'),
            items: [
              'Tunai',
              'Transfer',
            ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: busy ? null : (v) => setState(() => method = v!),
          ),
        ),
      const SizedBox(height: 28),
      Icon(
        paymentType == 'pickup'
            ? Icons.handshake_outlined
            : Icons.payments_outlined,
        size: 70,
        color: Theme.of(c).colorScheme.primary,
      ),
      const SizedBox(height: 20),
      Text(
        paymentType == 'pickup'
            ? 'Transaksi disimpan dengan status belum lunas. Pembayaran dicatat saat pengambilan.'
            : 'Pastikan pembayaran sudah diterima. Pilihan ini mencatat pembayaran, bukan memproses transfer otomatis.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Text(
        'Total tagihan ${rupiah(total)}',
        style: Theme.of(c).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
    ],
  );
}

String receiptText(Map<String, dynamic> d) {
  final b = StringBuffer();
  b.writeln('NOTA LAUNDRY • ${d['store']['name']}');
  b.writeln(d['store']['address']);
  b.writeln('Telp: ${d['store']['phone']}');
  b.writeln('\nNomor: ${d['number']}');
  b.writeln('Konsumen: ${d['customer']['name']}');
  b.writeln('HP: ${d['customer']['phone']}');
  b.writeln('Terima: ${orderDate(d['createdAt'])}');
  b.writeln('Estimasi selesai: ${orderDate(d['dueAt'])}');
  b.writeln('\nDetail pesanan:');
  for (final l in d['lines']) {
    b.writeln(
      '${l['name']}\n${l['quantity']} ${l['unit']} × ${rupiah(l['price'])} = ${rupiah(l['amount'])}',
    );
    if (l['note'] != '') b.writeln('Catatan: ${l['note']}');
  }
  b.writeln('\nTotal: ${rupiah(d['total'])}');
  b.writeln('Dibayar: ${rupiah(d['paid'])}');
  b.writeln('Sisa tagihan: ${rupiah(d['balance'])}');
  b.writeln('Pembayaran: ${d['paymentStatus']}');
  b.writeln('Status cucian: ${d['status']}');
  if (d['note'] != '') b.writeln('Keterangan: ${d['note']}');
  return b.toString();
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.store});
  final String store;
  @override
  State<OrdersPage> createState() => _OrdersState();
}

class _OrdersState extends State<OrdersPage> {
  String filter = 'Semua', search = '';
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Proses transaksi')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Cari nomor nota / konsumen',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['Semua', 'Baru', 'Diproses', 'Siap diambil', 'Diambil']
                .map(
                  (v) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(v),
                      selected: filter == v,
                      onSelected: (_) => setState(() => filter = v),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: Records(
            query: items(
              widget.store,
              'orders',
            ).orderBy('createdAt', descending: true),
            empty: 'Belum ada transaksi.',
            builder: (docs) {
              final rows = docs
                  .where(
                    (d) =>
                        (filter == 'Semua' || d.data()['status'] == filter) &&
                        '${d.data()['number']} ${d.data()['customer']['name']}'
                            .toLowerCase()
                            .contains(search),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (rows.isEmpty)
                    const Text('Tidak ada transaksi yang cocok.'),
                  for (final doc in rows)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${doc.data()['customer']['name']} • ${rupiah(doc.data()['total'])}',
                        ),
                        subtitle: Text(
                          '${doc.data()['number']}\n${doc.data()['status']} • ${doc.data()['paymentStatus']}\nSelesai: ${orderDate(doc.data()['dueAt'])}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          c,
                          MaterialPageRoute(
                            builder: (_) => OrderDetailPage(
                              store: widget.store,
                              id: doc.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.store,
    required this.id,
    this.created = false,
  });
  final String store, id;
  final bool created;
  @override
  State<OrderDetailPage> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<OrderDetailPage> {
  bool busy = false, sharing = false;
  Future<void> shareReceipt(Map<String, dynamic> d) async {
    final format = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Kirim nota sebagai'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'text'),
            child: const Text('Tulisan'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'image'),
            child: const Text('Gambar'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'pdf'),
            child: const Text('PDF'),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final asImage = format == 'image';
    setState(() => sharing = true);
    try {
      if (format != 'pdf' &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        final phone = whatsappPhone(d['customer']?['phone']?.toString() ?? '');
        final bytes = asImage
            ? await receiptImage(d, logo: await LaundryLogo.load(widget.store))
            : null;
        await WhatsappReceipt.send(
          phone: phone,
          text: receiptText(d),
          image: bytes,
        );
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      final bytes = format == 'pdf'
          ? await buildLaundryPdf(d, logo: await LaundryLogo.load(widget.store))
          : asImage
          ? await receiptImage(d, logo: await LaundryLogo.load(widget.store))
          : null;
      await SharePlus.instance.share(
        ShareParams(
          title: 'Nota ${d['number']}',
          text: format == 'text' ? receiptText(d) : null,
          files: bytes == null
              ? null
              : [
                  XFile.fromData(
                    bytes,
                    mimeType: format == 'pdf' ? 'application/pdf' : 'image/png',
                  ),
                ],
          fileNameOverrides: bytes == null
              ? null
              : ['nota-${d['number']}.${format == 'pdf' ? 'pdf' : 'png'}'],
          sharePositionOrigin: origin,
        ),
      );
    } on PlatformException catch (e) {
      if (mounted) message(context, e.message ?? 'Gagal membuka WhatsApp.');
    } catch (e) {
      if (mounted) message(context, errorText(e));
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  Map<String, dynamic>? pending;
  Future<void> mutate(Map<String, dynamic> data) async {
    setState(() => busy = true);
    pending ??= {...data, 'requestId': items(widget.store, 'orders').doc().id};
    try {
      await call('updateOrder', {
        'storeId': widget.store,
        'orderId': widget.id,
        ...pending!,
      });
      pending = null;
    } catch (e) {
      if (e is FormatException) {
        pending = null;
      }
      if (e is FirebaseException &&
          ![
            'unavailable',
            'deadline-exceeded',
            'internal',
            'unknown',
          ].contains(e.code)) {
        pending = null;
      }
      if (mounted) message(context, '${errorText(e)} Anda dapat mencoba lagi.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> printReceipt(Map<String, dynamic> d) async {
    try {
      final bytes = await buildLaundryPdf(
        d,
        logo: await LaundryLogo.load(widget.store),
      );
      await Printing.layoutPdf(
        name: 'nota-${d['number']}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) message(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Nota transaksi')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: items(widget.store, 'orders').doc(widget.id).snapshots(),
      builder: (c, s) {
        if (s.hasError) return Center(child: Text(errorText(s.error!)));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (!s.data!.exists) {
          return const Center(child: Text('Transaksi tidak tersedia.'));
        }
        final d = s.data!.data()!;
        final next = {
          'Baru': 'Diproses',
          'Diproses': 'Siap diambil',
          'Siap diambil': 'Diambil',
        }[d['status']];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.created) ...[
              const Icon(Icons.check_circle, color: Colors.teal, size: 64),
              const Text(
                'Transaksi telah dibuat',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: LaundryReceiptPreview(order: d, store: widget.store),
              ),
            ),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => printReceipt(d),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Cetak nota'),
                ),
                OutlinedButton.icon(
                  onPressed: sharing ? null : () => shareReceipt(d),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Kirim nota'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (pending != null)
              FilledButton(
                onPressed: busy ? null : () => mutate(pending!),
                child: const Text('Coba ulang perubahan sebelumnya'),
              ),
            if (pending == null && d['balance'] > 0)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final values = await form(
                          c,
                          'Catat pembayaran',
                          {'Nominal (Rp)': d['balance'].toString()},
                          requiredFields: {'Nominal (Rp)'},
                          numeric: {'Nominal (Rp)'},
                        );
                        if (values == null || !c.mounted) return;
                        final amount = int.tryParse(values['Nominal (Rp)']!);
                        if (amount == null ||
                            amount <= 0 ||
                            amount > d['balance']) {
                          message(
                            c,
                            'Isi nominal rupiah bulat, maksimal sisa tagihan.',
                          );
                          return;
                        }
                        final method = await showDialog<String>(
                          context: c,
                          builder: (c) => SimpleDialog(
                            title: const Text('Metode pembayaran'),
                            children: ['Tunai', 'Transfer']
                                .map(
                                  (v) => SimpleDialogOption(
                                    onPressed: () => Navigator.pop(c, v),
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                        if (method != null) {
                          await mutate({
                            'action': 'pay',
                            'amount': amount,
                            'method': method,
                          });
                        }
                      },
                child: const Text('Catat pembayaran / pelunasan'),
              ),
            if (pending == null && next != null)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(
                          c,
                          'Ubah status ke $next?',
                          next == 'Diambil'
                              ? 'Pastikan tagihan lunas dan cucian telah diserahkan.'
                              : 'Pastikan pekerjaan sudah sesuai status ini.',
                        )) {
                          await mutate({
                            'action': 'status',
                            'nextStatus': next,
                          });
                        }
                      },
                child: Text(busy ? 'Menyimpan…' : 'Tandai $next'),
              ),
            const SizedBox(height: 20),
            const Text(
              'Riwayat transaksi',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Records(
              query: items(
                widget.store,
                'orders',
              ).doc(widget.id).collection('events').orderBy('at'),
              builder: (docs) => Column(
                children: docs.map((e) {
                  final a = e.data();
                  return ListTile(
                    dense: true,
                    title: Text(
                      a['type'] == 'payment'
                          ? 'Pembayaran ${rupiah(a['amount'])} (${a['method']})'
                          : a['type'] == 'status'
                          ? '${a['from']} → ${a['to']}'
                          : 'Transaksi dibuat',
                    ),
                    subtitle: Text(orderDate(a['at'])),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Future<Uint8List> receiptImage(
  Map<String, dynamic> order, {
  Uint8List? logo,
}) async {
  final bytes = await buildLaundryPdf(order, logo: logo);
  final pages = await Printing.raster(bytes, dpi: 120).toList();
  final images = <ui.Image>[];
  try {
    for (final page in pages) {
      images.add(await page.toImage());
    }
    final width = images.fold<int>(
      0,
      (w, image) => image.width > w ? image.width : w,
    );
    final height = images.fold<int>(0, (h, image) => h + image.height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    double top = 0;
    for (final image in images) {
      canvas.drawImage(image, Offset(0, top), Paint());
      top += image.height;
    }
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    try {
      return (await result.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      result.dispose();
      picture.dispose();
    }
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

class LaundryReceiptPreview extends StatefulWidget {
  const LaundryReceiptPreview({
    super.key,
    required this.order,
    required this.store,
  });
  final Map<String, dynamic> order;
  final String store;
  @override
  State<LaundryReceiptPreview> createState() => _LaundryReceiptPreviewState();
}

class _LaundryReceiptPreviewState extends State<LaundryReceiptPreview> {
  late Future<Uint8List> preview;
  Future<Uint8List> render() async =>
      receiptImage(widget.order, logo: await LaundryLogo.load(widget.store));
  @override
  void initState() {
    super.initState();
    preview = render();
  }

  @override
  void didUpdateWidget(covariant LaundryReceiptPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order || oldWidget.store != widget.store) {
      preview = render();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: preview,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          children: [
            const Text('Pratinjau gagal dimuat.'),
            TextButton(
              onPressed: () => setState(() => preview = render()),
              child: const Text('Coba lagi'),
            ),
            SelectableText(receiptText(widget.order)),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(
        snapshot.data!,
        width: double.infinity,
        fit: BoxFit.contain,
      );
    },
  );
}

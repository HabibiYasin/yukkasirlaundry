import 'transaction_recap.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import 'store_summary.dart';
import 'orders.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'data.dart';
import 'service_excel.dart';

void message(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
Future<bool> confirm(BuildContext c, String title, String text) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    ) ??
    false;
Future<Map<String, String>?> form(
  BuildContext context,
  String title,
  Map<String, String> values, {
  Set<String> requiredFields = const {},
  Set<String> numeric = const {},
  bool fromContacts = false,
}) async {
  final controllers = values.map(
    (k, v) => MapEntry(k, TextEditingController(text: v)),
  );
  final key = GlobalKey<FormState>();
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controllers.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: e.value,
                        decoration: InputDecoration(labelText: e.key),
                        keyboardType: numeric.contains(e.key)
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        validator: (v) {
                          if (requiredFields.contains(e.key) &&
                              (v ?? '').trim().isEmpty) {
                            return 'Wajib diisi';
                          }
                          if (numeric.contains(e.key) &&
                              (num.tryParse(v ?? '') == null ||
                                  num.parse(v!) < 0)) {
                            return 'Isi angka minimal 0';
                          }
                          return null;
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      actions: [
        if (fromContacts &&
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS))
          TextButton.icon(
            icon: const Icon(Icons.contacts_outlined),
            label: const Text('Ambil dari kontak'),
            onPressed: () async {
              try {
                final contact = await FlutterNativeContactPicker()
                    .selectPhoneNumber();
                if (!c.mounted || contact == null) return;
                controllers['Nama']?.text = contact.fullName ?? '';
                controllers['Nomor HP']?.text =
                    contact.selectedPhoneNumber ??
                    (contact.phoneNumbers?.isNotEmpty == true
                        ? contact.phoneNumbers!.first
                        : '');
              } catch (_) {
                if (c.mounted) {
                  message(
                    c,
                    'Kontak tidak dapat dibuka. Silakan isi secara manual.',
                  );
                }
              }
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (key.currentState!.validate()) {
              Navigator.pop(
                c,
                controllers.map((k, v) => MapEntry(k, v.text.trim())),
              );
            }
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  // Dialog animation may still reference the controllers until the next frame.
  Future.delayed(const Duration(seconds: 1), () {
    for (final c in controllers.values) {
      c.dispose();
    }
  });
  return result;
}

class Records extends StatelessWidget {
  const Records({
    super.key,
    required this.query,
    required this.builder,
    this.empty = 'Belum ada data.',
  });
  final Query<Map<String, dynamic>> query;
  final Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>)
  builder;
  final String empty;
  @override
  Widget build(BuildContext c) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // A different query must not render the previous collection's snapshot.
        key: ValueKey(query),
        stream: query.snapshots(),
        builder: (c, s) {
          if (s.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(errorText(s.error!)),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(empty, textAlign: TextAlign.center)),
            );
          }
          return builder(s.data!.docs);
        },
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  String? selected;
  bool syncing = false;
  @override
  void initState() {
    super.initState();
    selected = widget.profile['lastStoreId'] as String?;
    sync();
  }

  Future<void> sync() async {
    setState(() => syncing = true);
    try {
      await auth.currentUser!.reload();
      await auth.currentUser!.getIdToken(true);
      await call('syncMemberships', {});
    } catch (e) {
      if (mounted) message(context, errorText(e));
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(['Beranda', 'Konsumen', 'Transaksi', 'Pengaturan'][tab]),
      actions: [
        IconButton(
          onPressed: syncing ? null : sync,
          tooltip: 'Sinkronkan akses toko',
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Beranda',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          label: 'Konsumen',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Transaksi',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          label: 'Pengaturan',
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('stores')
          .where('memberIds', arrayContains: auth.currentUser!.uid)
          .snapshots(),
      builder: (c, s) {
        if (s.hasError) return Center(child: Text(errorText(s.error!)));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final stores = s.data!.docs;
        final current =
            stores.where((d) => d.id == selected).firstOrNull ??
            stores.firstOrNull;
        final id = current?.id;
        return Column(
          children: [
            if (!auth.currentUser!.emailVerified)
              MaterialBanner(
                content: const Text(
                  'Verifikasi email untuk menerima akses toko sebagai karyawan.',
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      try {
                        await auth.currentUser!.sendEmailVerification();
                        if (c.mounted) {
                          message(
                            c,
                            'Email verifikasi dikirim. Setelah verifikasi, tekan sinkronkan.',
                          );
                        }
                      } catch (e) {
                        if (c.mounted) message(c, errorText(e));
                      }
                    },
                    child: const Text('Kirim email'),
                  ),
                ],
              ),
            Expanded(
              child: switch (tab) {
                0 => home(c, current),
                1 =>
                  id == null
                      ? const Center(
                          child: Text(
                            'Tambahkan toko atau tunggu undangan owner.',
                          ),
                        )
                      : CustomerPage(key: ValueKey(id), store: id),
                2 =>
                  id == null
                      ? const Center(
                          child: Text('Tambahkan toko di Pengaturan > Toko.'),
                        )
                      : TransactionRecapPage(
                          key: ValueKey(id),
                          store: id,
                          embedded: true,
                        ),
                _ => settings(c),
              },
            ),
          ],
        );
      },
    ),
  );
  Widget home(
    BuildContext c,
    QueryDocumentSnapshot<Map<String, dynamic>>? store,
  ) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xff24649a), Color(0xff378eb4)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SELAMAT DATANG',
              style: TextStyle(color: Colors.white70, letterSpacing: 2),
            ),
            const SizedBox(height: 8),
            Text(
              widget.profile['name'] ?? '',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${widget.profile['role']} • ${widget.profile['premium'] == true ? 'Premium' : 'Standar'}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: action(
              c,
              'Buat\nTransaksi',
              Icons.add_circle_outline,
              store?.id,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: action(
              c,
              'Proses\nTransaksi',
              Icons.local_laundry_service_outlined,
              store?.id,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Text('Ringkasan toko', style: Theme.of(c).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (store == null)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Mulai dengan menambahkan toko di Pengaturan > Toko. Untuk karyawan, toko muncul setelah email diundang owner.',
            ),
          ),
        )
      else ...[
        ListTile(
          leading: const Icon(Icons.storefront),
          title: Text(store.data()['name']),
          subtitle: Text(store.data()['address'] ?? ''),
        ),
        StoreSummary(key: ValueKey(store.id), store: store.id),
      ],
      const SizedBox(height: 20),
      const Text(
        'Buat pesanan, pantau pengerjaan, dan catat pembayaran per toko.',
        style: TextStyle(color: Colors.grey),
      ),
    ],
  );
  Widget action(BuildContext c, String title, IconData icon, String? store) =>
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (store == null) {
              message(c, 'Pilih atau tambahkan toko terlebih dahulu.');
              return;
            }
            Navigator.push(
              c,
              MaterialPageRoute(
                builder: (_) => title.startsWith('Buat')
                    ? CreateOrderPage(store: store)
                    : OrdersPage(store: store),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Icon(icon, size: 44, color: const Color(0xff24649a)),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
  Widget storeList(
    BuildContext c,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> stores,
  ) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        '${stores.length} toko terhubung',
        style: Theme.of(c).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      for (final d in stores)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.storefront)),
            title: Text(
              d.data()['name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${d.data()['city']}\n${d.data()['address']}'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => StorePage(id: d.id)),
            ),
          ),
        ),
      if (stores.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'Belum ada toko. Karyawan menggunakan email yang diundang owner, lalu menekan tombol sinkronkan.',
          ),
        ),
      if (widget.profile['role'] == 'Owner')
        FilledButton.icon(
          onPressed: () => addStore(c),
          icon: const Icon(Icons.add),
          label: const Text('Tambah toko'),
        ),
    ],
  );
  Future<void> addStore(BuildContext c) async {
    final v = await form(
      c,
      'Tambah toko',
      {'Nama toko': '', 'Nomor HP': '', 'Kota': '', 'Alamat': ''},
      requiredFields: {'Nama toko', 'Nomor HP', 'Kota', 'Alamat'},
    );
    if (v == null) return;
    final data = <String, dynamic>{
      'name': v['Nama toko'],
      'phone': v['Nomor HP'],
      'city': v['Kota'],
      'address': v['Alamat'],
    };
    try {
      final result = await call('createStore', data);
      if (result['duplicate'] == true && c.mounted) {
        if (await confirm(
          c,
          'Nama toko sudah ada',
          'Nama ini sudah pernah digunakan. Pastikan ini toko/cabang baru. Melanjutkan tidak menghubungkan akun ke toko yang sudah ada.',
        )) {
          await call('createStore', {...data, 'confirmDuplicate': true});
        }
      }
    } catch (e) {
      if (c.mounted) message(c, errorText(e));
    }
  }

  Future<void> openStores(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => Scaffold(
          appBar: AppBar(title: const Text('Toko')),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('stores')
                .where('memberIds', arrayContains: auth.currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text(errorText(snapshot.error!)));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final stores = snapshot.data!.docs;
              final active =
                  stores.where((d) => d.id == selected).firstOrNull ??
                  stores.firstOrNull;
              return Column(
                children: [
                  if (active != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(active.id),
                        initialValue: active.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Toko aktif',
                        ),
                        items: stores
                            .map(
                              (d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(
                                  d.data()['name'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) async {
                          if (id == null) return;
                          try {
                            await db
                                .collection('users')
                                .doc(auth.currentUser!.uid)
                                .update({'lastStoreId': id});
                            if (!mounted || !context.mounted) return;
                            setState(() => selected = id);
                            refresh(() {});
                          } catch (e) {
                            if (context.mounted) {
                              refresh(() {});
                              message(context, errorText(e));
                            }
                          }
                        },
                      ),
                    ),
                  Expanded(child: storeList(context, stores)),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget settings(BuildContext c) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      ListTile(
        leading: const Icon(Icons.storefront_outlined),
        title: const Text('Toko'),
        subtitle: const Text('Pilih toko aktif dan kelola toko'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openStores(c),
      ),
      Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(widget.profile['name']),
          subtitle: Text(auth.currentUser!.email ?? ''),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: const Text('Edit profil'),
        subtitle: const Text('Nama dan nomor HP'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final v = await form(
            c,
            'Edit profil',
            {
              'Nama': widget.profile['name'],
              'Nomor HP': widget.profile['phone'],
            },
            requiredFields: {'Nama', 'Nomor HP'},
          );
          if (v != null) {
            try {
              await db.collection('users').doc(auth.currentUser!.uid).update({
                'name': v['Nama'],
                'phone': v['Nomor HP'],
              });
            } catch (e) {
              if (c.mounted) message(c, errorText(e));
            }
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.print_outlined),
        title: const Text('Print'),
        subtitle: const Text('Cetak halaman uji melalui printer sistem'),
        onTap: () async {
          try {
            final doc = pw.Document();
            doc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a6,
                build: (_) => pw.Column(
                  children: [
                    pw.Text(
                      'YUK KASIR LAUNDRY',
                      style: pw.TextStyle(fontSize: 22),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text('Tes cetak berhasil'),
                    pw.Text(widget.profile['name']),
                  ],
                ),
              ),
            );
            await Printing.layoutPdf(onLayout: (_) => doc.save());
          } catch (e) {
            if (c.mounted) message(c, errorText(e));
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Tentang'),
        onTap: () => showAboutDialog(
          context: c,
          applicationName: 'Yuk Kasir Laundry',
          applicationVersion: '0.1.0',
          children: [
            const Text(
              'Aplikasi pengelolaan laundry.\nFlutter • Firebase\nTahap awal: toko, layanan, konsumen, dan karyawan.',
            ),
          ],
        ),
      ),
      ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Logout'),
        onTap: () async {
          if (await confirm(
            c,
            'Keluar akun?',
            'Anda dapat masuk kembali menggunakan email atau Google.',
          )) {
            await auth.signOut();
          }
        },
      ),
    ],
  );
}

class CustomerPage extends StatefulWidget {
  const CustomerPage({super.key, required this.store});
  final String store;
  @override
  State<CustomerPage> createState() => _CustomerState();
}

class _CustomerState extends State<CustomerPage> {
  String search = '';
  @override
  Widget build(BuildContext c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Cari nama / nomor telepon',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (s) => setState(() => search = s.toLowerCase()),
        ),
      ),
      Expanded(
        child: Records(
          query: items(widget.store, 'customers'),
          empty: 'Belum ada konsumen. Tambahkan konsumen pertama.',
          builder: (docs) {
            final rows = docs
                .where(
                  (d) => '${d.data()['name']} ${d.data()['phone']}'
                      .toLowerCase()
                      .contains(search),
                )
                .toList();
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('${rows.length} konsumen'),
                ),
                for (final d in rows)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(d.data()['name']),
                      subtitle: Text(d.data()['phone']),
                      onTap: () => edit(c, d),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: OutlinedButton.icon(
          onPressed: () => edit(c, null),
          icon: const Icon(Icons.add),
          label: const Text('Tambah konsumen baru'),
        ),
      ),
    ],
  );
  Future<void> edit(
    BuildContext c,
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  ) async {
    final d = doc?.data() ?? {};
    final v = await form(
      c,
      doc == null ? 'Tambah konsumen' : 'Edit konsumen',
      {
        'Nama': d['name'] ?? '',
        'Nomor HP': d['phone'] ?? '',
        'Alamat': d['address'] ?? '',
      },
      fromContacts: doc == null,
      requiredFields: {'Nama', 'Nomor HP'},
    );
    if (v == null) return;
    try {
      await (doc?.reference ?? items(widget.store, 'customers').doc()).set({
        'name': v['Nama'],
        'phone': v['Nomor HP'],
        'address': v['Alamat'],
      });
    } catch (e) {
      if (c.mounted) message(c, errorText(e));
    }
  }
}

class StorePage extends StatelessWidget {
  const StorePage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext c) => StreamBuilder(
    stream: db.collection('stores').doc(id).snapshots(),
    builder: (c, s) {
      if (!s.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final d = s.data!.data();
      if (d == null) {
        return const Scaffold(
          body: Center(child: Text('Toko tidak tersedia.')),
        );
      }
      final owner = d['ownerId'] == auth.currentUser!.uid;
      return Scaffold(
        appBar: AppBar(title: const Text('Detail toko')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Padding(
              padding: EdgeInsets.all(28),
              child: Icon(Icons.storefront, size: 88, color: Color(0xff24649a)),
            ),
            Text(
              d['name'],
              textAlign: TextAlign.center,
              style: Theme.of(c).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            for (final entry in {
              'Nomor HP': d['phone'],
              'Kota': d['city'],
              'Alamat': d['address'],
            }.entries)
              ListTile(
                title: Text(entry.key),
                subtitle: Text(entry.value ?? ''),
              ),
            if (owner)
              OutlinedButton(
                onPressed: () async {
                  final v = await form(
                    c,
                    'Edit detail toko',
                    {
                      'Nomor HP': d['phone'],
                      'Kota': d['city'],
                      'Alamat': d['address'],
                    },
                    requiredFields: {'Nomor HP', 'Kota', 'Alamat'},
                  );
                  if (v != null) {
                    try {
                      await s.data!.reference.update({
                        'phone': v['Nomor HP'],
                        'city': v['Kota'],
                        'address': v['Alamat'],
                      });
                    } catch (e) {
                      if (c.mounted) message(c, errorText(e));
                    }
                  }
                },
                child: const Text('Edit detail'),
              ),
            const Divider(),
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_laundry_service_outlined),
                title: const Text('Daftar layanan'),
                subtitle: const Text('Harga, durasi, dan biaya proses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => ServicesPage(store: id, owner: owner),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Daftar karyawan'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => MembersPage(store: id, owner: owner),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class MembersPage extends StatelessWidget {
  const MembersPage({super.key, required this.store, required this.owner});
  final String store;
  final bool owner;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Karyawan')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Anggota toko',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Records(
          query: items(store, 'members'),
          builder: (docs) => Column(
            children: docs
                .map(
                  (d) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(d.data()['name'] ?? ''),
                    subtitle: Text(
                      '${d.data()['email']} • ${d.data()['role']}',
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        if (owner) ...[
          const Divider(),
          const Text('Undangan karyawan'),
          Records(
            query: db
                .collection('invitations')
                .where('storeId', isEqualTo: store),
            empty: 'Belum ada undangan.',
            builder: (docs) => Column(
              children: docs
                  .map(
                    (d) => ListTile(
                      title: Text(d.data()['email']),
                      subtitle: Text(
                        d.data()['status'] == 'pending'
                            ? 'Menunggu login & verifikasi email'
                            : 'Sudah bergabung',
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final v = await form(
                c,
                'Tambah karyawan',
                {'Nama': '', 'Email login': ''},
                requiredFields: {'Nama', 'Email login'},
              );
              if (v == null) return;
              try {
                await call('inviteEmployee', {
                  'storeId': store,
                  'name': v['Nama'],
                  'email': v['Email login'],
                });
                if (c.mounted) {
                  message(
                    c,
                    'Undangan disimpan. Minta karyawan login dengan email tersebut, verifikasi email, lalu sinkronkan.',
                  );
                }
              } catch (e) {
                if (c.mounted) message(c, errorText(e));
              }
            },
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Tambah karyawan'),
          ),
        ],
      ],
    ),
  );
}

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key, required this.store, required this.owner});
  final String store;
  final bool owner;
  @override
  State<ServicesPage> createState() => _ServicesState();
}

class _ServicesState extends State<ServicesPage> {
  String search = '';
  bool busy = false;
  final money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) message(context, errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(QueryDocumentSnapshot<Map<String, dynamic>>? doc) async {
    final values = doc == null
        ? List<dynamic>.generate(
            19,
            (i) => i == 1
                ? 'PCS'
                : numericColumn(i)
                ? 0
                : '',
          )
        : List<dynamic>.from(doc.data()['values']);
    final v = await form(
      context,
      doc == null ? 'Tambah layanan' : 'Edit layanan',
      {for (var i = 0; i < 19; i++) serviceColumns[i]: values[i].toString()},
      requiredFields: {'Nama', 'Satuan'},
      numeric: {
        for (var i = 0; i < 19; i++)
          if (numericColumn(i)) serviceColumns[i],
      },
    );
    if (v == null) return;
    await run(() async {
      final row = validateService(serviceColumns.map((k) => v[k]).toList(), 1);
      await (doc?.reference ?? items(widget.store, 'services').doc()).set({
        'values': row,
      });
    });
  }

  Future<void> importFile() async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (file == null) return;
    final bytes = file.files.single.bytes;
    if (bytes == null) throw const FormatException('File tidak dapat dibaca.');
    final rows = decodeServices(bytes);
    if (rows.length > 450) {
      throw const FormatException(
        'Maksimal 450 layanan per impor agar penyimpanan atomik.',
      );
    }
    if (!mounted) return;
    if (!await confirm(
      context,
      'Impor ${rows.length} layanan?',
      'Data ditambahkan sebagai layanan baru. Layanan lama tidak ditimpa. Pastikan file ini belum pernah diimpor.',
    )) {
      return;
    }
    final batch = db.batch();
    for (final row in rows) {
      batch.set(items(widget.store, 'services').doc(), {'values': row});
    }
    await batch.commit();
    if (mounted) message(context, '${rows.length} layanan berhasil diimpor.');
  }

  Future<void> exportFile() async {
    final docs = await items(widget.store, 'services').get();
    final bytes = encodeServices(
      docs.docs.map((d) => List<dynamic>.from(d.data()['values'])).toList(),
    );
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Ekspor layanan',
      fileName: 'layanan_${widget.store}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: bytes,
    );
    if (path != null && mounted) {
      message(context, 'File layanan berhasil diekspor.');
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Daftar layanan')),
    floatingActionButton: busy
        ? null
        : FloatingActionButton(
            onPressed: () async {
              final choice = await showModalBottomSheet<String>(
                context: c,
                builder: (c) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.owner) ...[
                        ListTile(
                          leading: const Icon(Icons.add),
                          title: const Text('Tambah layanan baru'),
                          onTap: () => Navigator.pop(c, 'add'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.upload_file),
                          title: const Text('Impor layanan (.xlsx)'),
                          onTap: () => Navigator.pop(c, 'import'),
                        ),
                      ],
                      ListTile(
                        leading: const Icon(Icons.download),
                        title: const Text('Ekspor layanan (.xlsx)'),
                        onTap: () => Navigator.pop(c, 'export'),
                      ),
                    ],
                  ),
                ),
              );
              if (choice == 'add') {
                await edit(null);
              } else if (choice == 'import') {
                await run(importFile);
              } else if (choice == 'export') {
                await run(exportFile);
              }
            },
            child: const Icon(Icons.add),
          ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Cari layanan atau tags',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: Records(
            query: items(widget.store, 'services'),
            empty: 'Belum ada layanan. Gunakan tombol + untuk menambah atau impor Excel.',
            builder: (docs) {
              final filtered =
                  docs.where((d) {
                    final v = d.data()['values'];
                    return '${v[0]} ${v[7]}'.toLowerCase().contains(search);
                  }).toList()..sort(
                    (a, b) => a.data()['values'][0].toString().compareTo(
                      b.data()['values'][0].toString(),
                    ),
                  );
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                children: [
                  Text('${filtered.length} layanan'),
                  for (final d in filtered)
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(18),
                        title: Text(
                          d.data()['values'][0],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${d.data()['values'][2]} hari ${d.data()['values'][3]} jam\nMin. reguler ${d.data()['values'][5]} • deposit ${d.data()['values'][6]}\n${money.format(d.data()['values'][4])} / ${d.data()['values'][1]}',
                          ),
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          widget.owner
                              ? Icons.edit_outlined
                              : Icons.chevron_right,
                        ),
                        onTap: () => widget.owner
                            ? edit(d)
                            : showDialog<void>(
                                context: c,
                                builder: (c) => AlertDialog(
                                  title: Text(d.data()['values'][0]),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: List.generate(
                                        19,
                                        (i) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            '${serviceColumns[i]}: ${d.data()['values'][i]}',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Tutup'),
                                    ),
                                  ],
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

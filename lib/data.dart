import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const maxOrderLines = 4;
String keyHash(String value) =>
    base64UrlEncode(sha256.convert(utf8.encode(value)).bytes);
String normalizedStoreName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
String clean(dynamic v) => (v ?? '').toString().trim();
Never invalid(String message) => throw FormatException(message);
CollectionReference<Map<String, dynamic>> items(String store, String kind) =>
    db.collection('stores').doc(store).collection(kind);
String paymentStatus(num paid, num total) => paid == total
    ? 'Lunas'
    : paid == 0
    ? 'Belum lunas'
    : 'DP';

// All operations use the authenticated Firestore client; Security Rules validate
// every write, including atomic membership and payment changes.
Future<Map<String, dynamic>> call(
  String name,
  Map<String, dynamic> data,
) async {
  if (auth.currentUser == null) invalid('Silakan masuk terlebih dahulu.');
  return switch (name) {
    'completeProfile' => completeProfile(data),
    'createStore' => createStore(data),
    'inviteEmployee' => inviteEmployee(data),
    'syncMemberships' => syncMemberships(),
    'createOrder' => createOrder(data),
    'updateOrder' => updateOrder(data),
    _ => throw UnsupportedError(name),
  };
}

Future<Map<String, dynamic>> completeProfile(Map<String, dynamic> d) async {
  final u = auth.currentUser!, ref = db.collection('users').doc(u.uid);
  if (!['Owner', 'Karyawan'].contains(d['role']) ||
      clean(d['name']).isEmpty ||
      clean(d['phone']).isEmpty) {
    invalid('Lengkapi nama, nomor HP, dan peran.');
  }
  await db.runTransaction((t) async {
    if ((await t.get(ref)).exists) return;
    t.set(ref, {
      'id': u.uid,
      'name': clean(d['name']),
      'phone': clean(d['phone']),
      'email': u.email ?? '',
      'role': d['role'],
      'premium': false,
      'storeIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
  return {'ok': true};
}

Future<Map<String, dynamic>> createStore(Map<String, dynamic> d) async {
  final uid = auth.currentUser!.uid, name = clean(d['name']);
  if (name.isEmpty || name.length > 100) {
    invalid('Nama toko wajib diisi, maksimal 100 karakter.');
  }
  final key = keyHash(normalizedStoreName(name));
  final ref = db.collection('stores').doc(),
      index = db.collection('storeNames').doc(key),
      user = db.collection('users').doc(uid);
  return db.runTransaction((t) async {
    final profile = await t.get(user), existing = await t.get(index);
    if (profile.data()?['role'] != 'Owner') {
      invalid('Hanya owner dapat membuat toko.');
    }
    if (existing.exists && d['confirmDuplicate'] != true) {
      return {'duplicate': true};
    }
    t.set(ref, {
      'name': name,
      'nameKey': key,
      'duplicateConfirmed': d['confirmDuplicate'] == true,
      'phone': clean(d['phone']),
      'city': clean(d['city']),
      'address': clean(d['address']),
      'ownerId': uid,
      'memberIds': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (!existing.exists) t.set(index, {'storeId': ref.id});
    t.set(ref.collection('members').doc(uid), {
      'uid': uid,
      'name': profile.data()!['name'],
      'email': profile.data()!['email'],
      'role': 'Owner',
    });
    t.update(user, {
      'storeIds': FieldValue.arrayUnion([ref.id]),
      'lastStoreId': ref.id,
    });
    return {'id': ref.id};
  });
}

Future<Map<String, dynamic>> inviteEmployee(Map<String, dynamic> d) async {
  final email = clean(d['email']).toLowerCase(), store = clean(d['storeId']);
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    invalid('Email tidak valid.');
  }
  final ref = db.collection('invitations').doc(keyHash('$store:$email'));
  await db.runTransaction((t) async {
    if ((await t.get(ref)).exists) return;
    t.set(ref, {
      'storeId': store,
      'email': email,
      'name': clean(d['name']),
      'createdBy': auth.currentUser!.uid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
  return {'ok': true};
}

Future<Map<String, dynamic>> syncMemberships() async {
  final u = auth.currentUser!;
  if (!u.emailVerified) return {'linked': 0};
  final invites = await db
      .collection('invitations')
      .where('email', isEqualTo: u.email!.toLowerCase())
      .get();
  int linked = 0;
  for (final invite in invites.docs) {
    if (invite.data()['status'] != 'pending') continue;
    final added = await db.runTransaction((t) async {
      final fresh = await t.get(invite.reference);
      if (fresh.data()?['status'] != 'pending') return false;
      final ref = db.collection('stores').doc(fresh.data()!['storeId']),
          user = db.collection('users').doc(u.uid);
      final store = await t.get(ref), profile = await t.get(user);
      if (!store.exists || !profile.exists) return false;
      t.update(ref, {
        'memberIds': FieldValue.arrayUnion([u.uid]),
      });
      t.set(ref.collection('members').doc(u.uid), {
        'uid': u.uid,
        'name': profile.data()!['name'],
        'email': profile.data()!['email'],
        'role': store.data()!['ownerId'] == u.uid ? 'Owner' : 'Karyawan',
      });
      t.update(user, {
        'storeIds': FieldValue.arrayUnion([ref.id]),
        'lastStoreId': ref.id,
      });
      t.update(invite.reference, {'status': 'accepted', 'uid': u.uid});
      return true;
    });
    if (added) linked++;
  }
  return {'linked': linked};
}

Future<Map<String, dynamic>> createOrder(Map<String, dynamic> d) async {
  final storeId = clean(d['storeId']), uid = auth.currentUser!.uid;
  final ref = items(storeId, 'orders').doc(d['requestId']);
  return db.runTransaction((t) async {
    final old = await t.get(ref);
    if (old.exists) return {'id': ref.id};
    final store = await t.get(db.collection('stores').doc(storeId)),
        customer = await t.get(
          items(storeId, 'customers').doc(d['customerId']),
        );
    if (!store.exists || !customer.exists) {
      invalid('Toko atau konsumen tidak tersedia.');
    }
    final inputs = List<Map<String, dynamic>>.from(d['lines']);
    if (inputs.isEmpty || inputs.length > maxOrderLines) {
      invalid('Pilih 1 sampai $maxOrderLines layanan per transaksi.');
    }
    final lines = <Map<String, dynamic>>[];
    int total = 0, maxHours = 0;
    for (final input in inputs) {
      final service = await t.get(
        items(storeId, 'services').doc(input['serviceId']),
      );
      if (!service.exists) invalid('Layanan tidak tersedia.');
      final v = service.data()!['values'] as List;
      final quantity = (input['quantity'] as num).toDouble(),
          price = v[4] as num;
      if (!quantity.isFinite ||
          quantity <= 0 ||
          quantity > 100000 ||
          quantity < (v[5] as num) ||
          (quantity * 100 - (quantity * 100).round()).abs() > 0.00001) {
        invalid('Kuantitas ${v[0]} tidak valid atau kurang dari minimum.');
      }
      if (input['expectedPrice'] != price) {
        invalid('Harga berubah. Pilih ulang layanan untuk memperbarui harga.');
      }
      final amount = (quantity * price).round(),
          hours = ((v[2] as num) * 24 + (v[3] as num)).toInt();
      total += amount;
      maxHours = math.max(maxHours, hours);
      lines.add({
        'serviceId': service.id,
        'name': v[0],
        'unit': v[1],
        'price': price,
        'quantity': quantity,
        'amount': amount,
        'note': clean(input['note']),
        'durationHours': hours,
      });
    }
    // Longest service first keeps rules validation within the expression budget.
    lines.sort(
      (a, b) =>
          (b['durationHours'] as int).compareTo(a['durationHours'] as int),
    );
    if (total > 1000000000) invalid('Total transaksi terlalu besar.');
    final type = d['paymentType'];
    if (!['paid', 'deposit', 'pickup'].contains(type)) {
      invalid('Pilih tipe pembayaran.');
    }
    final paid = type == 'paid'
        ? total
        : type == 'pickup'
        ? 0
        : d['paid'];
    if (paid is! int ||
        paid < 0 ||
        paid > total ||
        (type == 'deposit' && (paid <= 0 || paid >= total))) {
      invalid('Nominal pembayaran tidak valid.');
    }
    final method = paid > 0 ? d['paymentMethod'] : '';
    if (paid > 0 && !['Tunai', 'Transfer'].contains(method)) {
      invalid('Pilih metode pembayaran.');
    }
    final now = Timestamp.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch,
        ),
        storeData = store.data()!;
    t.set(ref, {
      'number': 'YK-${ref.id}',
      'store': {
        'name': storeData['name'],
        'address': storeData['address'],
        'phone': storeData['phone'],
      },
      'customer': {'id': customer.id, ...customer.data()!},
      'lines': lines,
      'total': total,
      'paid': paid,
      'balance': total - paid,
      'paymentType': type,
      'paymentMethod': method,
      'paymentStatus': paymentStatus(paid, total),
      'status': 'Baru',
      'note': clean(d['note']),
      'createdAt': now,
      'dueAt': Timestamp.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch + maxHours * 3600000,
      ),
      'createdBy': uid,
      'lastEventId': 'created',
    });
    t.set(ref.collection('events').doc('created'), {
      'type': 'created',
      'uid': uid,
      'at': FieldValue.serverTimestamp(),
      'paid': paid,
      'method': method,
    });
    return {'id': ref.id};
  });
}

Future<Map<String, dynamic>> updateOrder(Map<String, dynamic> d) async {
  final ref = items(d['storeId'], 'orders').doc(d['orderId']),
      uid = auth.currentUser!.uid;
  final event = ref.collection('events').doc(d['requestId']);
  await db.runTransaction((t) async {
    final snap = await t.get(ref), previous = await t.get(event);
    if (previous.exists) return;
    if (!snap.exists) invalid('Transaksi tidak tersedia.');
    final order = snap.data()!;
    if (d['action'] == 'pay') {
      final amount = d['amount'];
      if (amount is! int || amount <= 0 || amount > order['balance']) {
        invalid('Nominal melebihi sisa tagihan atau tidak valid.');
      }
      if (!['Tunai', 'Transfer'].contains(d['method'])) {
        invalid('Metode pembayaran tidak valid.');
      }
      final paid = (order['paid'] as num) + amount;
      t.update(ref, {
        'paid': paid,
        'balance': order['total'] - paid,
        'paymentStatus': paymentStatus(paid, order['total']),
        'lastEventId': event.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      t.set(event, {
        'type': 'payment',
        'uid': uid,
        'at': FieldValue.serverTimestamp(),
        'amount': amount,
        'method': d['method'],
      });
    } else if (d['action'] == 'status') {
      final next = {
        'Baru': 'Diproses',
        'Diproses': 'Siap diambil',
        'Siap diambil': 'Diambil',
      }[order['status']];
      if (next == null || next != d['nextStatus']) {
        invalid('Status sudah berubah. Muat ulang transaksi.');
      }
      if (next == 'Diambil' && order['balance'] > 0) {
        invalid('Lunasi tagihan sebelum pengambilan.');
      }
      t.update(ref, {
        'status': next,
        'lastEventId': event.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      t.set(event, {
        'type': 'status',
        'uid': uid,
        'at': FieldValue.serverTimestamp(),
        'from': order['status'],
        'to': next,
      });
    } else {
      invalid('Aksi tidak valid.');
    }
  });
  return {'ok': true};
}

String errorText(Object e) {
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-credential' => 'Email atau kata sandi salah.',
      'email-already-in-use' => 'Email sudah terdaftar. Silakan masuk.',
      'weak-password' => 'Gunakan kata sandi minimal 6 karakter.',
      'invalid-email' => 'Format email tidak valid.',
      'operation-not-allowed' => 'Provider login belum diaktifkan di Firebase.',
      'network-request-failed' => 'Periksa koneksi internet Anda.',
      _ => e.message ?? 'Login gagal.',
    };
  }
  if (e is FirebaseException) {
    return switch (e.code) {
      'permission-denied' => 'Akses ditolak. Pastikan akun memiliki akses toko dan email undangan sudah diverifikasi.',
      'unavailable' =>
        'Tidak dapat terhubung ke Firebase. Periksa internet, lalu coba lagi.',
      'failed-precondition' => 'Data berubah atau konfigurasi database belum siap. Muat ulang dan coba lagi.',
      _ => e.message ?? 'Penyimpanan gagal.',
    };
  }
  return e.toString().replaceFirst('FormatException: ', '');
}

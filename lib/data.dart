import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
Future<Map<String, dynamic>> call(
  String name,
  Map<String, dynamic> data,
) async => Map<String, dynamic>.from(
  (await FirebaseFunctions.instance.httpsCallable(name).call(data)).data as Map,
);
CollectionReference<Map<String, dynamic>> items(String store, String kind) =>
    db.collection('stores').doc(store).collection(kind);
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
  if (e is FirebaseFunctionsException) return e.message ?? 'Permintaan gagal.';
  return e.toString().replaceFirst('FormatException: ', '');
}

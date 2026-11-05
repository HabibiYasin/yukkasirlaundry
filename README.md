# Yuk Kasir Laundry

Aplikasi Flutter Android/iOS dengan Firebase Authentication dan Cloud Firestore langsung pada project `yuk-kasir-laundry`. Tidak menggunakan Cloud Functions; tidak perlu mengaktifkan Blaze untuk fitur yang ada. Pemakaian tetap mengikuti kuota paket Spark.

## Menjalankan ke cloud (default)

1. Pastikan Email/Password dan Google sudah Enabled di Firebase Console > Authentication.
2. Buka emulator Android lewat Android Studio.
3. Di VS Code, pilih **Yuk Kasir Laundry - Cloud (Spark)** pada Run and Debug, lalu F5.

Atau jalankan `flutter run` tanpa `USE_EMULATORS=true`. Firebase Emulator tidak perlu dinyalakan. Paket debug cloud: `build/app/outputs/flutter-apk/app-debug.apk`.

Akun login tersimpan di Authentication. Setelah mengisi nama, nomor HP dan role lalu menekan **Mulai**, profil tersimpan di Firestore `users/{uid}`. Akun dan data yang dibuat di emulator sebelumnya tidak otomatis pindah ke cloud. Daftar kembali di cloud jika akun sebelumnya hanya ada di emulator.

Firebase client configuration (`google-services.json`, `firebase_options.dart`) bukan admin credential. Jangan memasukkan service account, keystore, atau private key ke repository. Debug SHA-1 sudah didaftarkan; rilis memerlukan sertifikat release/Play App Signing. iOS tetap memerlukan macOS/Xcode dan konfigurasi Google URL scheme.

## Fitur

- Login/daftar email-password dan Google; profil Owner/Karyawan, nomor HP, status premium dan banyak toko.
- Pembuatan toko dengan konfirmasi nama duplikat. Nama sama tidak memberikan akses ke toko lain.
- Undangan karyawan berdasarkan email. Karyawan perlu memverifikasi email lalu login/sinkronkan untuk menghubungkan ke toko.
- Daftar/edit layanan 19 kolom, impor-ekspor XLSX, konsumen dan pencarian.
- Transaksi: konsumen > layanan/kuantitas > keranjang > lunas/DP/bayar saat pengambilan > nota.
- Baru > Diproses > Siap diambil > Diambil; pengambilan mensyaratkan lunas.
- Cetak PDF melalui printer sistem, berbagi nota teks, riwayat status/pembayaran.
- Promo dan pajak tidak termasuk sesuai permintaan. Cetak label/ESC-POS belum tersedia.

## Validasi Firestore

Semua penulisan aplikasi melewati Security Rules. Role/premium tidak dapat dinaikkan sendiri. Membership hanya dapat ditambah melalui undangan email terverifikasi. Harga, nama layanan, minimum, kuantitas, total, snapshot konsumen/toko dan pembayaran dicek rules terhadap data toko. Pembayaran dan histori harus ditulis atomik; request ID mencegah pengulangan pembayaran saat retry.

Maksimal **4 baris layanan per transaksi** agar validasi harga seluruh baris tetap di bawah batas akses dokumen Security Rules. Layanan tambahan dicatat di transaksi berikutnya. Minimum reguler berlaku; DP pembayaran bukan minimum order deposit/saldo pelanggan. Harga dibulatkan per baris ke rupiah bulat. Estimasi mengikuti durasi terlama. Waktu perangkat harus akurat (toleransi waktu transaksi 5 menit).

Operasi transaksi toko/undangan/pembayaran memerlukan internet. Impor maksimal 450 baris layanan per batch; data ditambahkan setelah seluruh baris valid. Premium hanya dapat diubah oleh admin melalui lingkungan tepercaya.

## Struktur data

- `users/{uid}`: id, name, email, phone, role, premium, storeIds, lastStoreId, createdAt.
- `stores/{id}`: name, nameKey, duplicateConfirmed, phone, city, address, ownerId, memberIds, createdAt.
- `stores/{id}/members/{uid}`: uid, name, email, role.
- `stores/{id}/services/{id}`: values (19 kolom Excel).
- `stores/{id}/customers/{id}`: name, phone, address.
- `stores/{id}/orders/{id}`: snapshot dan total, paid, balance, status, paymentStatus, createdAt, dueAt, lastEventId.
- `stores/{id}/orders/{id}/events/{requestId}`: histori immutable untuk pembuatan, pembayaran dan status.
- `invitations/{hash}`: undangan/claim terverifikasi.
- `storeNames/{hash}`: indeks nama untuk konfirmasi duplikat.

Hash baru menggunakan SHA-256 Base64 URL-safe (termasuk padding). Data emulator lama tidak dimigrasikan. Nomor nota memakai ID dokumen unik, bukan urutan global.

## Pengujian lokal opsional

Mode lokal hanya untuk pengujian; tidak menjadi konfigurasi utama aplikasi. Java 21+ diperlukan untuk Firebase Emulator.

```powershell
flutter pub get
flutter analyze
flutter test
npm install --prefix firestore_tests
firebase emulators:exec --config firebase.spark-test.json --only firestore --project demo-yuk-spark "npm test --prefix firestore_tests"
```

Tes Spark memakai SDK client terautentikasi dan Security Rules sungguhan, tanpa admin bypass untuk skenario transaksi. Suite mencakup pendaftaran, duplikat toko, invitation claim, penolakan eskalasi privilege, isolasi toko, 4 layanan, harga/total palsu, pembayaran atomik/idempoten, serta pelunasan sebelum pengambilan.

Untuk mencoba UI memakai emulator lokal:

```powershell
firebase emulators:start --only "auth,firestore" --project yuk-kasir-laundry
flutter run --dart-define=USE_EMULATORS=true
```

## Deploy aturan

```powershell
firebase deploy --only firestore:rules --project yuk-kasir-laundry
```

Tidak ada deploy Functions atau perubahan penagihan. Snapshot data lama tidak dihapus. Referensi: https://firebase.google.com/docs/firestore/security/rules-conditions dan https://firebase.google.com/docs/projects/billing/firebase-pricing-plans

Verifikasi migrasi Spark: 12 tes Security Rules lulus (termasuk batch 450 layanan), 4 tes Flutter lulus, `flutter analyze` tanpa issue, dan APK debug cloud berhasil dibangun. Rules telah dideploy ke `yuk-kasir-laundry`. Login pada perangkat/cloud belum diuji memakai akun pengguna.

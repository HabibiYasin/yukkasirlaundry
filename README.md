# Yuk Kasir

Aplikasi mobile Flutter untuk laundry. Firebase project: `yuk-kasir-laundry`.

## Fitur tahap awal

- Masuk/daftar email dan Google, pemilihan Owner atau Karyawan.
- Profil: ID Firebase Auth, nama, email, nomor HP, role, premium, daftar ID toko.
- Navigasi Beranda, Konsumen, Toko, Pengaturan.
- Banyak toko, detail toko, konfirmasi nama toko yang sudah pernah terdaftar.
- Undangan karyawan berdasarkan email terverifikasi. Login/sinkronisasi menghubungkan data toko owner.
- Tambah/edit konsumen dan pencarian nama/nomor HP.
- Tambah/edit layanan dengan seluruh 19 kolom Excel contoh; impor dan ekspor XLSX.
- Edit profil, cetak halaman uji PDF melalui printer sistem, tentang, logout.
- Transaksi: pilih/tambah konsumen, layanan dan kuantitas, keranjang, pembayaran lunas/DP/saat pengambilan, nota PDF dan berbagi nota teks.
- Proses: Baru > Diproses > Siap diambil > Diambil; pembayaran terpisah, pelunasan wajib sebelum pengambilan; riwayat pembayaran/status.
- Detail acuan video dan batas implementasi: [docs/transaction-flow.md](docs/transaction-flow.md).

## Status Firebase

Aplikasi Android dan iOS telah terdaftar. Firestore database dibuat oleh Firebase CLI di region default `nam5`, dan security rules telah dideploy. SHA-1 debug Android telah didaftarkan.

Cloud Functions BELUM dideploy: project masih Spark; deployment meminta Blaze. Penagihan tidak diubah sesuai permintaan pengguna. `completeProfile`, `createStore`, `inviteEmployee`, `syncMemberships`, `createOrder`, `updateOrder` memerlukan Functions sehingga alur tersebut hanya bisa digunakan di emulator sampai Functions dideploy.

Provider Email/Password dan Google harus diaktifkan pada Firebase Console > Authentication > Sign-in method. Google OAuth belum diverifikasi. Setelah mengaktifkan Google, jalankan ulang `flutterfire configure --project=yuk-kasir-laundry --platforms=android,ios` untuk mengambil konfigurasi OAuth terbaru. iOS juga memerlukan URL scheme REVERSED_CLIENT_ID dari GoogleService-Info.plist pada Info.plist, serta build melalui macOS/Xcode. Jangan menggunakan APK debug untuk rilis Play Store.

## Menjalankan lokal tanpa Blaze

Prasyarat: Flutter, Node 22, Firebase CLI, Java 21+ untuk emulator. Instal dependency:

```powershell
flutter pub get
npm install --prefix functions
firebase emulators:start --project yuk-kasir-laundry --only auth,firestore,functions
```

Terminal kedua, Android emulator:

```powershell
flutter run --dart-define=USE_EMULATORS=true
```

Untuk perangkat Android fisik pada jaringan yang sama:

```powershell
flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=IP_KOMPUTER
```

Gunakan email/password pada emulator. Link verifikasi email tampil di terminal Auth Emulator. Data emulator terpisah dari produksi. Google native memerlukan konfigurasi OAuth nyata.

## Pengujian

```powershell
flutter analyze
flutter test
firebase emulators:exec --only firestore --project demo-yuk-kasir "npm test --prefix functions"
flutter build apk --debug
```

Tes Excel menggunakan file contoh asli, menguji 19 kolom, harga tidak valid, dan round-trip ekspor/impor. Tes security rules memeriksa isolasi toko, perubahan layanan oleh owner, akses konsumen, serta penolakan eskalasi role/premium/keanggotaan.

## Struktur Firestore

- `users/{uid}`: id, name, email, phone, role, premium, storeIds, createdAt.
- `stores/{storeId}`: name, phone, city, address, ownerId, memberIds, createdAt.
- `stores/{storeId}/members/{uid}`: uid, name, email, role.
- `stores/{storeId}/services/{id}`: values (19 nilai sesuai urutan header Excel).
- `stores/{storeId}/customers/{id}`: name, phone, address.
- `invitations/{hash}`: storeId, email, name, createdBy, status, uid setelah diterima.
- `stores/{storeId}/orders/{id}`: snapshot toko/konsumen/layanan, total, paid, balance, status, paymentStatus, createdAt, dueAt, createdBy.
- `stores/{storeId}/orders/{id}/events/{id}`: audit pencatatan transaksi, pembayaran dan perubahan status; hanya Functions yang dapat menulis.
- `storeNames/{hash}`: penanda nama yang dinormalisasi untuk pemeriksaan duplikat.

Premium hanya dapat diubah backend/admin. Nama toko sama tidak memberikan akses ke toko lain. Nama toko belum dapat diubah agar indeks duplikat konsisten. Owner dapat mengedit layanan; karyawan dapat melihat/mengekspor layanan dan mengelola konsumen. Impor bersifat tambah, maksimal 450 baris per file, divalidasi seluruhnya sebelum batch atomik. Impor file yang sama dua kali akan menambahkan duplikat setelah konfirmasi.

## Setelah Blaze diaktifkan (opsional, ditunda)

```powershell
firebase deploy --only functions --project yuk-kasir-laundry
```

Jangan mengaktifkan billing tanpa keputusan pemilik project. Bluetooth ESC/POS, cetak label, pemrosesan pembayaran otomatis, promo/pajak, pemindahan owner, dan penghapusan karyawan/toko belum termasuk tahap ini. Pencatatan pembayaran manual dan pencetakan nota melalui printer sistem sudah tersedia.

Referensi setup: https://firebase.google.com/docs/flutter/setup dan https://firebase.google.com/docs/auth/flutter/federated-auth

## Hasil verifikasi 5 November 2026

- `flutter analyze`: tanpa issue.
- `flutter test`: 4 tes Excel/nota lulus.
- Firestore Emulator: 7 tes aturan akses lulus.
- Auth + Firestore + Functions Emulator: pendaftaran profil, penolakan pembuatan toko oleh karyawan, konfirmasi nama duplikat, undangan email terverifikasi, sinkronisasi dan idempotensi lulus.
- `flutter build apk --debug`: berhasil. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Belum diuji pada perangkat Android/iOS fisik, printer fisik, atau login Google produksi.

Tes integrasi backend dapat diulang dengan:

```powershell
firebase emulators:exec --only auth,firestore,functions --project demo-yuk-kasir "node functions/integration.cjs"
```

APK default menggunakan Firebase online; profil/toko tetap menunggu Functions aktif. Untuk seluruh flow lokal, jalankan/build dengan `--dart-define=USE_EMULATORS=true` dan hidupkan emulator Firebase. Pada Windows, bila Java default versi 17, arahkan JAVA_HOME/PATH ke JBR Android Studio (Java 21+) untuk Firebase Emulator.

Tes integrasi transaksi mencakup total Rp39.000 sesuai video, harga otoritatif server, minimum order, akses anggota, tiga tipe pembayaran, idempotensi pembayaran, transisi status, dan pengambilan setelah lunas. Perubahan transaksi tahap ini belum dideploy ke Firebase online.

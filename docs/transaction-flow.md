# Acuan transaksi dari video

Sumber: WhatsApp Video 2026-11-05 at 14.18.33.mp4 (sekitar 58 detik). Video dipakai sebagai referensi perilaku; nama dan data konsumen di dalamnya tidak diimpor ke aplikasi.

## Yang terlihat

1. Beranda > Buat Transaksi.
2. Cari konsumen dengan nama/nomor HP; tersedia Tambah Konsumen Baru.
3. Pilih layanan, isi kuantitas, catatan opsional, tambah ke keranjang. Dapat memilih lebih dari satu layanan.
4. Keranjang menampilkan konsumen, layanan, kuantitas, harga, total, estimasi selesai, dan keterangan.
5. Pembayaran memiliki pilihan Lunas Saat Ini, DP, atau Bayar Saat Pengambilan.
6. Pilihan bayar saat pengambilan menyimpan transaksi dengan sisa tagihan penuh.
7. Halaman sukses menyediakan lihat nota, cetak nota, kirim nota, dan cetak label.
8. Kirim nota membuka pemilih aplikasi/kontak, kemudian nota teks dibagikan ke WhatsApp.

Contoh yang terlihat: Cuci Lipat 2 Jam, 3 KG x Rp7.000 = Rp21.000; Cuci Lipat 6 Jam, 3 KG x Rp6.000 = Rp18.000; total Rp39.000. Estimasi selesai memakai layanan terlama (6 jam).

## Implementasi tahap ini

- Pemilihan konsumen atau tambah konsumen; pemilihan beberapa layanan; edit/hapus item; catatan item/transaksi; keranjang; ketiga tipe pembayaran.
- Metode Tunai dan Transfer dicatat manual. Aplikasi tidak menginisiasi transfer bank.
- Harga, minimum reguler, total, snapshot konsumen/layanan/toko, dan estimasi dihitung/ditetapkan server. Perubahan harga sebelum checkout ditolak agar pengguna meninjau ulang.
- Pengulangan request simpan/pembayaran tidak menggandakan transaksi/pembayaran.
- Nota ditampilkan, dicetak melalui PDF/printer sistem, atau dibagikan melalui share sheet. Pengguna sendiri memilih WhatsApp dan penerima.
- Proses yang disetujui pengguna: Baru > Diproses > Siap diambil > Diambil. Pengambilan mensyaratkan saldo tagihan nol. Riwayat perubahan dan pembayaran disimpan.
- Backend tetap Cloud Functions lokal/emulator; Blaze tidak diaktifkan. Tidak ada deploy baru pada tahap ini.

## Belum ditentukan / belum diimplementasikan

- Video tidak memperlihatkan konfigurasi promo/kupon, pajak/biaya tambahan, pengantaran, express, parfum, dan spesifikasi barang. Aturannya menunggu penjelasan pengguna.
- Cetak label dan integrasi printer Bluetooth ESC/POS belum diimplementasikan.
- Proses produksi/pengambilan tidak diperlihatkan di video; status di atas dikonfirmasi pengguna secara terpisah dari video.
- Pembatalan/refund, koreksi transaksi setelah disimpan, diskon khusus, produk nonlayanan, dan deposit saldo pelanggan belum termasuk.
- Minimum order saat ini menolak kuantitas di bawah minimum reguler; tidak melakukan pembulatan tagihan otomatis.

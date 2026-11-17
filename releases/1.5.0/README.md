# AimLock 1.5.0: panel minimal dan identitas author

Paket repository berada di `releases/1.5.0/`, termasuk script, manifest, `config/` dan README ini. [Panduan struktur repository dan SOP build](../../docs/release-structure.md). Lokasi file setelah dipasang dalam game tetap mengikuti prosedur instalasi di bawah.

Versi ini mengganti antarmuka 1.4.0 dengan panel dua menu: Pengaturan dan Log. Command default menjadi `/apanel`, toggle tracking menjadi Alt + X. Identitas pada chat dan kanan atas panel mengikuti metadata author: **IronForgez | Arvin_Inc**. Nama file dan `script_name` tetap AimLock.

## Tampilan dan interaksi

Panel berjudul **Panel**, ukuran awal maksimal 860 x 580 sesuai ruang layar, terpusat saat pertama dibuka dan tetap dapat diubah ukurannya. Header menampilkan status ON/OFF serta Alt + X di kiri, author diratakan ke kanan berdasarkan lebar teks. Jika keduanya tidak muat dalam satu baris, author tetap di baris atas dan status pindah ke baris berikutnya. Sidebar berisi dua menu tanpa heading, paragraf instruksi atau tombol tutup tambahan. Escape atau X jendela menutup panel.

Pengaturan langsung menampilkan **Acak titik**, **Jarak** dan **Interval (ms)**. Bagian **Distribusi** dilipat secara default dan membuka enam bobot beserta totalnya. **Lanjutan** menampung startup, FOV, offset tinggi, crosshair, seed, telemetry, command, ukuran teks, Muat INI, Default dan Batalkan. Bagian form dapat discroll; status validasi dan dua tombol utama tetap terpisah di bawah:

| Kontrol | Hasil |
| --- | --- |
| Simpan | Validasi, backup INI, simpan dan terapkan |
| Terapkan | Validasi dan terapkan untuk sesi berjalan |
| Muat INI / Default / Batalkan | Ubah draft; tidak langsung menerapkan |
| Alt + X | ON/OFF ketika panel ditutup; satu toggle per chord |
| Ctrl + X | Tidak mengubah status tracking |

Halaman Log memprioritaskan tabel, pencarian, Sesi aktif dan Refresh. **Filter & berkas** melipat kontrol berkas, event, ID target, refresh otomatis, Cari berkas dan Kosongkan tampilan. **Detail** melipat pratinjau JSON event terpilih. Status kosong, loading, kesalahan baca dan validasi tetap tersedia. Kosongkan tampilan hanya mengosongkan memori; berkas tidak dihapus. Refresh otomatis, batas memori dan pembacaan bertahap dari 1.4.0 tetap berlaku.

Label berkas dan pratinjau detail memakai alias tampilan netral: teks AimLock ditampilkan sebagai Panel, dan `aimlock_enabled` sebagai `tracking_enabled`. Ini berlaku untuk tampilan saja; nama berkas, raw JSONL, field telemetry dan data di disk tidak diubah. Penampil teks dinamis juga menerapkan penyamaran identitas sehingga path/error log lama tidak memunculkan nama script sebagai branding GUI. Detail adalah pratinjau untuk dibaca, bukan salinan JSON byte asli.

Chat startup diringkas menjadi satu baris, misalnya:

```text
[IronForgez | Arvin_Inc] /apanel | Alt + X: ON/OFF | OFF
[IronForgez | Arvin_Inc] ON
[IronForgez | Arvin_Inc] OFF
```

Saat GUI terbuka, target dilepas dan penulisan kamera serta toggle Alt + X diblokir. Status ON/OFF dipertahankan ketika konfigurasi diterapkan; checkbox Aktif saat masuk tetap mengatur startup berikutnya. Tracking, weighted point selection, passive telemetry dan schema laporan tetap mengikuti versi sebelumnya. Semua hasil telemetry masih laporan client dengan status server unknown.

## Instalasi dan migrasi

1. Pindahkan script versi lama dan source `AimLock.lua` keluar dari folder script aktif. Pasang hanya satu versi.
2. Salin [AimLock1.5.0.lua](AimLock1.5.0.lua) ke `moonloader/` dan [AimLock1.5.0.ini](config/AimLock1.5.0.ini) ke `moonloader/config/`.
3. Pertahankan mimgui v1.7.1 di `moonloader/lib/mimgui/`, termasuk DLL dan semua file Lua. Tidak ada dependensi baru. [ZIP resmi](https://github.com/THE-FYP/mimgui/releases/download/v1.7.1/mimgui-v1.7.1.zip).
4. Jika ingin memakai nilai lama, salin pengaturan numerik/distribusi ke INI 1.5.0. Default bobot tetap 20/20/20/15/15/10; validasi total 100%, bobot nonnegatif dan rentang lainnya tidak berubah.
5. Masuk game, buka `/apanel`, pilih Pengaturan/Log; tutup sebelum memakai Alt + X.

Konfigurasi command terbaru:

```ini
[aimlock]
gui_enabled=true
gui_command=apanel
```

Hanya satu command yang didaftarkan. Tidak ada alias `/aimlock` atau `/aimlog`. Nama command kustom tetap dapat digunakan untuk menghindari bentrok: 1..20 karakter a-z/0-9/underscore, diawali huruf, tanpa slash. `gui_command` dan `gui_enabled` berlaku setelah reload script. Command yang sudah didefinisikan script client lain tidak ditimpa; pesan author menjelaskan bentrok. Jika panel bentrok, ubah INI dan reload.

Untuk kompatibilitas membaca INI lama, `gui_command=aimlock` atau `aimlog` dinormalisasi menjadi `apanel`. Key lama `gui_log_command` tetap divalidasi sebagai string command, lalu diabaikan dan tidak ditulis lagi saat Simpan. Tidak ada command kedua walaupun key tersebut dibaca. Migrasi parser ini tidak menulis ulang INI 1.4.0 secara otomatis.

File log baru tetap bernama `AimLock1.5.0-<waktu>-<game_ms>-<urutan>.jsonl` di `moonloader/logs/`. Manifest JSON hanya metadata checksum, tidak diperlukan untuk menjalankan script. Folder source `lib/AimLockDistribution` tidak diperlukan oleh bundle. File log/manifest tidak dipasang ke `lib`. Fallback tanpa mimgui tetap menyediakan konfigurasi INI dan Alt + X, dengan alasan GUI OFF pada `moonloader.log`.

## Modul dan alur

Bundle berisi 18 modul. Modul baru **identity.lua** menyimpan author, versi sesi telemetry, prefix chat, dan pemetaan identitas untuk tampilan. Metadata script menggunakan author yang sama; nama file/script tetap terpisah dari identitas presentasi.

| Modul yang berubah | Tanggung jawab aktual |
| --- | --- |
| AimLock.lua | Entry, prefix author, startup ringkas, INI 1.5.0 dan pembacaan VK_MENU (0x12) + X (0x58) |
| controller.lua | Debounce berdasarkan `input.alt` dan `input.x`; jalur Ctrl dihapus |
| gui.lua | Dua menu, header author kanan, bagian yang dilipat dan penampil teks netral |
| gui_runtime.lua | Pendaftaran satu command dan polling Log pada menu kedua |
| settings.lua, config_store.lua | Default apanel, migrasi command lama dan serialisasi satu command |
| gui_model.lua | Draft/apply/save tetap terpisah, pesan status lebih ringkas |
| telemetry.lua, telemetry_runtime.lua | Versi sesi 1.5.0 dan prefix author melalui identity; format data tidak diubah |

Config, random, engine, aim_point, camera, world, observer, journal dan log_view mempertahankan algoritma/kontrak sebelumnya. Observer tidak menulis packet atau membatalkan event. Save dan baca berkas tetap diproses di loop utama, bukan callback render. Simpan mempertahankan backup dan penggantian file Windows dari [1.4.0](../1.4.0/README.md).

## Pengembangan dan publikasi

```powershell
# Memerlukan source terbaru lokal:
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools

# Bisa dijalankan pada clone publik:
luajit tests/aimlock_spec.lua releases/1.5.0/AimLock1.5.0.lua
luajit tests/shot_telemetry_spec.lua releases/1.5.0/AimLock1.5.0.lua
luajit tests/gui_spec.lua releases/1.5.0/AimLock1.5.0.lua
luajit tests/windows_io_spec.lua releases/1.5.0/AimLock1.5.0.lua
```

Update ini mempublikasikan artifact obfuscated, manifest, INI, tes, tools dan dokumentasi melalui allowlist file eksplisit. Perubahan source terbaru disimpan lokal. Snapshot source lama sudah dilacak di Git melalui commit pengguna sebelum update ini; riwayat/file lama itu tidak dihapus atau diperbarui oleh commit publikasi GUI 1.5.0. Snapshot lama tersebut bukan source build 1.5.0. Jangan men-stage source terbaru atau JSONL ketika memperbarui bundle. Obfuscation tidak menjamin kode tidak dapat dipulihkan.

## Verifikasi

76 kelompok tes lulus pada source dan bundle di LuaJIT 2.0.1774896119, LuaJIT 2.1.1774896198 dan Lua 5.1: 30 aim tracking, 26 telemetry dan 20 GUI (456 kelulusan kelompok; nol gagal). Tes memastikan `/apanel` tunggal, dua command lama tidak didaftarkan, Ctrl + X tidak toggle, debounce Alt + X, pemblokiran saat GUI terbuka, author kanan atas melalui koordinat layout, field tersembunyi saat bagian dilipat, seluruh aksi/control, penyamaran teks GUI termasuk log versi lama, serta raw log yang tidak berubah.

Tes Windows I/O lulus pada source/bundle di kedua LuaJIT menggunakan kernel32 dan berkas sementara nyata, termasuk backup, file terkunci dan retry. Build/check memeriksa sintaks Lua 5.1, main/onExitScript, bundle 18 modul dan checksum terhadap source/INI lokal. Runtime test memakai Lupa Windows x64 sementara, bukan MoonLoader x86/GTA.

| Gate UI | Hasil dan bukti |
| --- | --- |
| PASS: perilaku / state | Renderer stub menguji dua menu, foldout, input, aksi dan tutup; keseimbangan scope diuji termasuk error render |
| PASS: identitas / hierarki | Author dihitung dari batas kanan dan lebar teks; default hanya tiga field utama, dua foldout dan dua aksi; tidak ada teks AimLock dalam output render/chat yang diuji |
| PASS: arah visual | Panel utilitas minimal sesuai permintaan pengguna, ENERGY 1 / RHYTHM 1 / MOTION 1; warna slate solid dan aksen biru lama dipertahankan untuk fokus/kontrol, tanpa aset/dekorasi baru |
| PASS: kontras palet | Palet 1.4.0 tetap; teks utama/hover 8.25:1, teks sekunder/hover 5.24:1, border/hover 3.56:1, aksen/hover 6.08:1, teks pada pilihan 4.79:1 dan pilihan/panel 3.01:1 |
| Belum diuji: native UI | GTA/MoonLoader DX9 tidak tersedia; tampilan nyata, tab/fokus keyboard, author pada berbagai DPI, Alt kiri/kanan, cursor, scrolling dan kontrol pemain masih perlu diuji langsung |

API CollapsingHeader, CalcTextSize, GetWindowContentRegionMax dan SetCursorPosX diperiksa pada wrapper rilis mimgui v1.7.1. Navigasi keyboard dan Escape tetap diaktifkan. Hasil stub/koordinat tidak dinyatakan sebagai bukti kelulusan rendering native atau registrasi hit server.

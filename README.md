# AimLock 1.4.0

Penguncian arah kamera ke pemain SA-MP yang terlihat dekat crosshair, dengan **random aim berbobot selama lock** dan toggle **Ctrl + X**. Status awal **OFF**. Setelah ON, tahan **klik kanan** untuk mempertahankan pemain yang sama; titik aim memilih ulang torso, lengan, kaki, atau kepala setiap 300 ms secara default.

Versi 1.4.0 menambahkan **GUI konfigurasi dan pembaca log dengan sidebar**. Buka `/aimlock` untuk mengatur tracking, distribusi, dan telemetry; `/aimlog` langsung membuka halaman log. Draft dapat diterapkan ke sesi berjalan atau disimpan ke INI dengan backup.

Versi [1.3.0](docs/AimLock-shot-telemetry-1.3.0.md) memperkenalkan telemetry. Versi [1.1.0](docs/AimLock.md) memakai satu titik tetap. Versi [1.2.0](docs/AimLock-random-aim-1.2.0.md) menghubungkan engine Weighted Random lama dengan penguncian kamera. Versi [1.0.0](docs/AimLock-simulator-1.0.0.md) tetap merupakan arsip simulator distribusi hit.

## Instalasi

Siapkan GTA San Andreas Windows, SA-MP, MoonLoader, dan SAMPFUNCS yang kompatibel. Salin dua file ini:

```text
GTA San Andreas/
  moonloader/
    AimLock1.4.0.lua
    config/
      AimLock1.4.0.ini
    lib/
      mimgui/          # dependensi GUI, dari ZIP resmi
```

- [Unduh AimLock1.4.0.lua](moonloader/AimLock1.4.0.lua)
- [Unduh AimLock1.4.0.ini](moonloader/config/AimLock1.4.0.ini)
- [Manifest SHA256](moonloader/AimLock1.4.0.manifest.json)
- [mimgui v1.7.1 resmi](https://github.com/THE-FYP/mimgui/releases/download/v1.7.1/mimgui-v1.7.1.zip): ekstrak folder `mimgui` ke `moonloader/lib/`, termasuk DLL dan semua file Lua di dalamnya.

Pasang hanya satu versi script. Pindahkan source `AimLock.lua` dan versi distribusi lama keluar dari folder MoonLoader jika memasang versi ini. Folder `lib/AimLockDistribution` tidak diperlukan untuk versi obfuscated; tujuh belas modul sudah dibundel. Folder `lib/mimgui` diperlukan untuk GUI. Jika mimgui atau API GUI tidak tersedia, script tetap menggunakan INI dan Ctrl + X, dengan alasan kegagalan di `moonloader.log`. File JSON manifest adalah metadata build dan tidak perlu dipasang. `ffi` sudah merupakan bagian LuaJIT; jangan memasang file ffi dari sumber lain.

## Penggunaan

1. Masuk SA-MP dan spawn. Pesan startup menampilkan status OFF.
2. Tekan dan lepas **Ctrl + X**. Chat lokal menampilkan `[AimLock] ON`.
3. Dengan senjata ID 22..32 dan karakter berjalan kaki, tahan klik kanan dan arahkan crosshair dekat pemain yang terlihat.
4. Kamera mengikuti pemain tersebut dan memilih ulang bagian tubuh setiap interval. Pemilihan bisa menghasilkan bagian yang sama beberapa kali berturut-turut.
5. Lepas klik kanan untuk melepas target. Tekan **Ctrl + X** lagi untuk OFF.

Menahan Ctrl + X tidak menyebabkan toggle berulang. Panel GUI, chat, dialog, console SAMPFUNCS, pause, kehilangan fokus, belum spawn, dan putus koneksi menghentikan penulisan kamera. Keybind diabaikan saat UI tersebut aktif. Script tidak menembak otomatis atau memodifikasi packet/damage. Command `/hitdist` hanya tersedia pada versi simulator lama.

## Panel konfigurasi dan log

| Command / kontrol | Fungsi |
| --- | --- |
| `/aimlock` | Membuka halaman Konfigurasi |
| `/aimlog` | Membuka halaman Log |
| Terapkan | Memvalidasi dan menerapkan draft tanpa menyimpan INI |
| Simpan & Terapkan | Menyimpan INI dengan backup `.bak`, lalu menerapkan |
| Muat INI / Default / Batalkan draft | Mengisi ulang draft; belum mengubah sesi berjalan |
| Escape / Tutup panel / tombol X jendela | Menutup panel |
| Ukuran teks | Mengubah ukuran teks panel 1x..2x selama sesi GUI |

Halaman Distribusi menyediakan enam bobot, interval dan seed. Total wajib 100%, nol diizinkan. Halaman Telemetry mengatur pencatatan, jendela korelasi dan interval tulis. Konfigurasi diterapkan tanpa mengubah status ON/OFF saat ini; `enabled` mengatur status saat script dimuat. Setiap penerapan memulai sesi telemetry baru jika pencatatan aktif.

Halaman Log memiliki pilihan file, filter event/ID target, pencarian isi, tabel event dan detail JSON. Refresh otomatis berjalan setiap 500 ms selama halaman Log terbuka. **Bersihkan tampilan** tidak menghapus file. Command diperiksa sebelum didaftarkan; jika bentrok, ubah `gui_command` atau `gui_log_command` pada INI lalu reload script. Nama command dan `gui_enabled` berlaku setelah reload.

## Shot Telemetry

Dengan `telemetry_enabled=true`, log dibuat otomatis di `moonloader/logs/AimLock1.4.0-<waktu>-<game_ms>-<urutan>.jsonl`. File JSONL adalah hasil pengamatan yang dibuat saat bermain, bukan file instalasi yang perlu disalin ke `lib`. Satu baris memuat satu event JSON. Pencatatan berjalan juga saat aim tracking OFF agar tembakan biasa dapat dibandingkan dengan mode ON.

`shot` menyimpan snapshot titik pilihan dan laporan BulletSync; `damage_report` menyimpan body part serta damage yang dilaporkan client. `correlation_update` memberi kandidat hubungan berdasarkan ID pemain, senjata, dan waktu. Korelasi tembakan cepat bisa ambigu. Tidak adanya laporan pasangan tidak langsung diberi label miss, dan **laporan client bukan konfirmasi damage server**. Semua event memakai `server_status=unknown`.

Observer memulihkan posisi baca bitstream dan tidak mengganti payload atau membatalkan paket. Log ditulis secara batch di loop utama. Jika API telemetry atau penulisan log gagal, status dicatat di `moonloader.log` dan aim tracking tetap tersedia. Tidak diperlukan SAMP.Lua; mimgui hanya diperlukan untuk GUI.

## Konfigurasi

Gunakan `/aimlock`, atau edit `moonloader/config/AimLock1.4.0.ini` lalu pilih Muat INI dan Terapkan (alternatif: reload script). Pengaturan random aim, telemetry, dan GUI:

```ini
[aimlock]
random_aim=true
random_interval_ms=300
random_seed=auto
telemetry_enabled=true
telemetry_match_window_ms=750
telemetry_flush_interval_ms=1000
gui_enabled=true
gui_command=aimlock
gui_log_command=aimlog

[distribution]
torso=20
left_arm=20
right_arm=20
left_leg=15
right_leg=15
head=10
```

Bobot di atas mengikuti INI simulator lama pengguna dan harus berjumlah 100. Nol diizinkan. `random_aim=false` memakai titik tetap seperti versi 1.1.0. Pengacakan berdasarkan waktu selama lock, bukan per peluru. Probabilitas ini mengatur pemilihan titik aim, bukan menjamin persentase hit atau damage server.

`telemetry_enabled=false` mematikan pencatatan secara terpisah dari Ctrl + X. `telemetry_match_window_ms` mengatur jendela kandidat korelasi 50..3000 ms; `telemetry_flush_interval_ms` mengatur interval tulis 100..10000 ms. Semua interval harus integer.

`max_distance` adalah jarak dunia game; `fov_radius` menentukan radius pencarian awal. Ketika random aim aktif, FOV tidak melepas pemain yang sudah terkunci hanya karena titik tubuh berpindah. Target tetap harus hidup, terlihat, dalam jarak, serta memiliki garis pandang pada titik acuannya. `target_height` menggeser tinggi seluruh titik. Nilai `crosshair_x/y` dapat disesuaikan dengan posisi crosshair HUD pengguna.

Titik target memakai offset posisi ped, bukan bone tracking. Senjata scope/ID 33 ke atas dan drive-by belum didukung. Akurasi dengan mod HUD, animasi, skin, dan aspek layar pengguna perlu diuji dalam game.

## Pengembangan dan verifikasi

Source `moonloader/AimLock.lua`, `moonloader/lib/AimLockDistribution/`, dan arsip source disimpan lokal dan tidak disertakan dalam publikasi. Repository memuat versi distribusi obfuscated beserta konfigurasi, manifest, tes, dan dokumentasi. Log runtime diabaikan melalui `moonloader/logs/.gitignore`. Obfuscation mempersulit pembacaan dan tidak menjamin kode tidak dapat dipulihkan.

```powershell
# Tes bundle; tidak memerlukan source lokal:
luajit tests/aimlock_spec.lua moonloader/AimLock1.4.0.lua
luajit tests/shot_telemetry_spec.lua moonloader/AimLock1.4.0.lua
luajit tests/gui_spec.lua moonloader/AimLock1.4.0.lua
luajit tests/windows_io_spec.lua moonloader/AimLock1.4.0.lua

# Build ulang; memerlukan source lokal:
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
```

[Dokumentasi GUI 1.4.0, arsitektur, dependensi dan SOP](docs/AimLock-GUI-1.4.0.md) menjelaskan perubahan terbaru. [Dokumentasi Shot Telemetry 1.3.0](docs/AimLock-shot-telemetry-1.3.0.md) menyimpan rincian schema yang tetap relevan. Tes aim/telemetry/GUI memakai stub MoonLoader dan mimgui; tes Windows I/O memakai kernel32 dan file sementara nyata. Pengujian tampilan serta input langsung di GTA/SA-MP belum dijalankan.

# AimLock 1.5.1

Penguncian arah kamera ke pemain SA-MP yang terlihat dekat crosshair, dengan **random aim berbobot selama lock** dan toggle **Alt + X**. Status awal **OFF**. Setelah ON, tahan **klik kanan** untuk mempertahankan pemain yang sama; titik aim memilih ulang torso, lengan, kaki, atau kepala setiap 300 ms secara default.

Versi 1.5.1 memperbaiki panel yang langsung menjadi GUI OFF pada bundle 1.5.0 akibat argumen numerik tambahan ke `TextUnformatted`. Detail penyebab, perbaikan dan pengujian FFI tersedia di [catatan 1.5.1](releases/1.5.1/README.md).

Panel tetap memakai dua menu, **Pengaturan** dan **Log**, melalui **`/apanel`**. Opsi lanjutan dilipat, author **IronForgez | Arvin_Inc** tampil di kanan atas, dan chat memakai prefix `[IronForgez | Arvin_Inc]`. Nama AimLock dipertahankan untuk identitas file/script dan data internal; tampilan panel/chat memakai identitas author. Toggle tetap **Alt + X** seperti versi 1.5.0.

Versi [1.4.0](releases/1.4.0/README.md) memperkenalkan GUI. Versi [1.3.0](releases/1.3.0/README.md) memperkenalkan telemetry. Versi [1.1.0](releases/1.1.0/README.md) memakai satu titik tetap. Versi [1.2.0](releases/1.2.0/README.md) menghubungkan engine Weighted Random lama dengan penguncian kamera. Versi [1.0.0](releases/1.0.0/README.md) tetap merupakan arsip simulator distribusi hit.

## Struktur rilis

```text
releases/
  1.0.0/
  1.1.0/
  1.2.0/
  1.3.0/
  1.4.0/
  1.5.0/
  1.5.1/
    AimLock1.5.1.lua
    AimLock1.5.1.manifest.json
    README.md
    config/
      AimLock1.5.1.ini
moonloader/
  AimLock.lua                    source pengembangan lokal
  lib/AimLockDistribution/        modul pengembangan lokal
```

Setiap folder versi berisi script obfuscated, manifest, dokumentasi dan konfigurasi yang sesuai. Versi 1.0.0 memakai nama konfigurasi lama `config/AimLock.ini`. Source terbaru tetap lokal; snapshot source lama yang sudah ada di Git dipertahankan. [Panduan struktur, build dan publikasi](docs/release-structure.md).

## Instalasi

Siapkan GTA San Andreas Windows, SA-MP, MoonLoader, dan SAMPFUNCS yang kompatibel. Pilih satu folder versi di `releases/`. Untuk 1.5.1, salin `releases/1.5.1/AimLock1.5.1.lua` ke `moonloader/` game dan `releases/1.5.1/config/AimLock1.5.1.ini` ke `moonloader/config/` game. Pengguna 1.5.0 dapat menyalin INI lama menjadi `AimLock1.5.1.ini` untuk mempertahankan pengaturan:

```text
GTA San Andreas/
  moonloader/
    AimLock1.5.1.lua
    config/
      AimLock1.5.1.ini
    lib/
      mimgui/          # dependensi GUI, dari ZIP resmi
```

- [Unduh AimLock1.5.1.lua](releases/1.5.1/AimLock1.5.1.lua)
- [Unduh AimLock1.5.1.ini](releases/1.5.1/config/AimLock1.5.1.ini)
- [Manifest SHA256](releases/1.5.1/AimLock1.5.1.manifest.json)
- [mimgui v1.7.1 resmi](https://github.com/THE-FYP/mimgui/releases/download/v1.7.1/mimgui-v1.7.1.zip): ekstrak folder `mimgui` ke `moonloader/lib/`, termasuk DLL dan semua file Lua di dalamnya.

Pasang hanya satu versi script. Pindahkan source `AimLock.lua` dan versi distribusi lama keluar dari folder MoonLoader jika memasang versi ini. Folder `lib/AimLockDistribution` tidak diperlukan untuk versi obfuscated; delapan belas modul sudah dibundel. Folder `lib/mimgui` diperlukan untuk GUI. Jika mimgui atau API GUI tidak tersedia, script tetap menggunakan INI dan Alt + X, dengan alasan kegagalan di `moonloader.log`. File JSON manifest adalah metadata build dan tidak perlu dipasang. `ffi` sudah merupakan bagian LuaJIT; jangan memasang file ffi dari sumber lain.

## Penggunaan

1. Masuk SA-MP dan spawn. Pesan startup menampilkan status OFF.
2. Tekan dan lepas **Alt + X**. Chat lokal menampilkan `[IronForgez | Arvin_Inc] ON`.
3. Dengan senjata ID 22..32 dan karakter berjalan kaki, tahan klik kanan dan arahkan crosshair dekat pemain yang terlihat.
4. Kamera mengikuti pemain tersebut dan memilih ulang bagian tubuh setiap interval. Pemilihan bisa menghasilkan bagian yang sama beberapa kali berturut-turut.
5. Lepas klik kanan untuk melepas target. Tekan **Alt + X** lagi untuk OFF.

Menahan Alt + X tidak menyebabkan toggle berulang. Ctrl + X tidak mengaktifkan tracking. Panel GUI, chat, dialog, console SAMPFUNCS, pause, kehilangan fokus, belum spawn, dan putus koneksi menghentikan penulisan kamera. Keybind diabaikan saat UI tersebut aktif. Script tidak menembak otomatis atau memodifikasi packet/damage. Command `/hitdist` hanya tersedia pada versi simulator lama.

## Panel konfigurasi dan log

| Command / kontrol | Fungsi |
| --- | --- |
| `/apanel` | Membuka panel; pilih Pengaturan atau Log pada sidebar |
| Terapkan | Memvalidasi dan menerapkan draft tanpa menyimpan INI |
| Simpan | Menyimpan INI dengan backup `.bak`, lalu menerapkan |
| Lanjutan: Muat INI / Default / Batalkan | Mengisi ulang draft; belum mengubah sesi berjalan |
| Escape / tombol X jendela | Menutup panel |
| Lanjutan: Ukuran teks | Mengubah ukuran teks panel 1x..2x selama sesi GUI |

Pengaturan utama menampilkan Acak titik, Jarak dan Interval. Buka **Distribusi** untuk enam bobot; total wajib 100%, nol diizinkan. **Lanjutan** memuat FOV, offset, crosshair, seed, startup, telemetry, command dan ukuran teks. Konfigurasi diterapkan tanpa mengubah status ON/OFF saat ini; `enabled` mengatur status saat script dimuat. Setiap penerapan memulai sesi telemetry baru jika pencatatan aktif.

Log menampilkan Sesi aktif, Refresh, pencarian dan tabel. **Filter & berkas** menyimpan pemilihan file, filter event/ID target, refresh otomatis dan Kosongkan tampilan; **Detail** menampilkan pratinjau event. Refresh otomatis berjalan setiap 500 ms selama halaman Log terbuka. Kosongkan tampilan tidak menghapus file. Command diperiksa sebelum didaftarkan; jika bentrok, ubah `gui_command` pada INI lalu reload script. Nama command dan `gui_enabled` berlaku setelah reload. Parser menerima key lama `gui_log_command` untuk migrasi, tetapi tidak mendaftarkan command kedua atau menuliskan key tersebut saat Simpan.

## Shot Telemetry

Dengan `telemetry_enabled=true`, log dibuat otomatis di `moonloader/logs/AimLock1.5.1-<waktu>-<game_ms>-<urutan>.jsonl`. File JSONL adalah hasil pengamatan yang dibuat saat bermain, bukan file instalasi yang perlu disalin ke `lib`. Satu baris memuat satu event JSON. Pencatatan berjalan juga saat aim tracking OFF agar tembakan biasa dapat dibandingkan dengan mode ON. Nama/path/identitas internal ditampilkan sebagai alias netral dalam GUI; isi berkas asli tetap dipertahankan.

`shot` menyimpan snapshot titik pilihan dan laporan BulletSync; `damage_report` menyimpan body part serta damage yang dilaporkan client. `correlation_update` memberi kandidat hubungan berdasarkan ID pemain, senjata, dan waktu. Korelasi tembakan cepat bisa ambigu. Tidak adanya laporan pasangan tidak langsung diberi label miss, dan **laporan client bukan konfirmasi damage server**. Semua event memakai `server_status=unknown`.

Observer memulihkan posisi baca bitstream dan tidak mengganti payload atau membatalkan paket. Log ditulis secara batch di loop utama. Jika API telemetry atau penulisan log gagal, status dicatat di `moonloader.log` dan aim tracking tetap tersedia. Tidak diperlukan SAMP.Lua; mimgui hanya diperlukan untuk GUI.

## Konfigurasi

Gunakan `/apanel`, atau edit `moonloader/config/AimLock1.5.1.ini` lalu pilih Lanjutan > Muat INI dan Terapkan (alternatif: reload script). Pengaturan random aim, telemetry, dan GUI:

```ini
[aimlock]
random_aim=true
random_interval_ms=300
random_seed=auto
telemetry_enabled=true
telemetry_match_window_ms=750
telemetry_flush_interval_ms=1000
gui_enabled=true
gui_command=apanel

[distribution]
torso=20
left_arm=20
right_arm=20
left_leg=15
right_leg=15
head=10
```

Bobot di atas mengikuti INI simulator lama pengguna dan harus berjumlah 100. Nol diizinkan. `random_aim=false` memakai titik tetap seperti versi 1.1.0. Pengacakan berdasarkan waktu selama lock, bukan per peluru. Probabilitas ini mengatur pemilihan titik aim, bukan menjamin persentase hit atau damage server.

`telemetry_enabled=false` mematikan pencatatan secara terpisah dari Alt + X. `telemetry_match_window_ms` mengatur jendela kandidat korelasi 50..3000 ms; `telemetry_flush_interval_ms` mengatur interval tulis 100..10000 ms. Semua interval harus integer.

`max_distance` adalah jarak dunia game; `fov_radius` menentukan radius pencarian awal. Ketika random aim aktif, FOV tidak melepas pemain yang sudah terkunci hanya karena titik tubuh berpindah. Target tetap harus hidup, terlihat, dalam jarak, serta memiliki garis pandang pada titik acuannya. `target_height` menggeser tinggi seluruh titik. Nilai `crosshair_x/y` dapat disesuaikan dengan posisi crosshair HUD pengguna.

Titik target memakai offset posisi ped, bukan bone tracking. Senjata scope/ID 33 ke atas dan drive-by belum didukung. Akurasi dengan mod HUD, animasi, skin, dan aspek layar pengguna perlu diuji dalam game.

## Pengembangan dan verifikasi

Update 1.5.1 mempublikasikan bundle obfuscated, konfigurasi, manifest, tes dan dokumentasi. Perubahan source terbaru pada `moonloader/AimLock.lua` dan `moonloader/lib/AimLockDistribution/` tetap lokal. Snapshot source lama sudah tercatat di repository melalui commit sebelum update ini; file/history tersebut tidak dihapus oleh perbaikan ini. Build 1.5.1 memerlukan source terbaru lokal, bukan snapshot lama itu. Log runtime diabaikan melalui `moonloader/logs/.gitignore`. Obfuscation mempersulit pembacaan dan tidak menjamin kode tidak dapat dipulihkan.

```powershell
# Tes bundle; tidak memerlukan source lokal:
luajit tests/aimlock_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/shot_telemetry_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/gui_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/gui_ffi_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/windows_io_spec.lua releases/1.5.1/AimLock1.5.1.lua

# Build ulang; memerlukan source lokal:
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
```

[Catatan perbaikan panel 1.5.1](releases/1.5.1/README.md) menjelaskan bug dan tes regresi. [Dokumentasi GUI minimal 1.5.0](releases/1.5.0/README.md), [GUI 1.4.0](releases/1.4.0/README.md) dan [telemetry 1.3.0](releases/1.3.0/README.md) menjadi referensi versi sebelumnya. Tes aim/telemetry/GUI memakai stub MoonLoader dan mimgui; tes batas FFI dan Windows I/O memakai LuaJIT dengan signature native/kernel32 nyata. Log kegagalan dalam game sudah dianalisis, tetapi tampilan serta input langsung setelah perbaikan belum diuji di GTA/SA-MP.

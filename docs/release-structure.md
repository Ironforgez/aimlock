# Struktur rilis AimLock

Paket distribusi dikelompokkan berdasarkan nomor versi di `releases/<versi>/`. Pemindahan ini mempertahankan byte script obfuscated dan INI; logika game, keybind, command, schema dan dependensi tidak berubah. Manifest hanya memperbarui path artifact/configuration relatif terhadap root repository. Hash source historis dan SHA256 artifact/INI tetap dipertahankan.

| Versi | Paket dan dokumentasi | Perilaku versi |
| --- | --- | --- |
| 1.0.0 | [releases/1.0.0](../releases/1.0.0/README.md) | Simulator distribusi |
| 1.1.0 | [releases/1.1.0](../releases/1.1.0/README.md) | Tracking titik tetap |
| 1.2.0 | [releases/1.2.0](../releases/1.2.0/README.md) | Weighted aim point |
| 1.3.0 | [releases/1.3.0](../releases/1.3.0/README.md) | Passive shot telemetry |
| 1.4.0 | [releases/1.4.0](../releases/1.4.0/README.md) | GUI konfigurasi/log |
| 1.5.0 | [releases/1.5.0](../releases/1.5.0/README.md) | Panel minimal, apanel, Alt + X |
| 1.5.1 | [releases/1.5.1](../releases/1.5.1/README.md) | Perbaikan argumen teks GUI/FFI pada bundle 1.5.0 |

Setiap paket berisi `AimLock<versi>.lua`, `AimLock<versi>.manifest.json`, `README.md` dan `config/AimLock<versi>.ini`. Pengecualian 1.0.0 adalah nama INI `config/AimLock.ini` karena itulah nama yang dibaca simulator. Artifact/manifest 1.0.0 berasal dari arsip obfuscated lokal yang checksum-nya sudah diverifikasi; source arsip `.source.lua` tetap pada arsip lokal.

## Repository dan instalasi game

`releases/` adalah lokasi paket dalam repository. Pilih satu versi, salin file Lua paket ke `GTA San Andreas/moonloader/` dan salin INI paket ke `GTA San Andreas/moonloader/config/`. Struktur dalam game tetap memakai `moonloader/config/`, sehingga string path yang sudah dibundel tidak perlu diubah. Manifest dan README digunakan untuk verifikasi/panduan; mimgui tetap mengikuti instalasi versi yang dipilih.

Source pengembangan tetap di `moonloader/AimLock.lua` dan `moonloader/lib/AimLockDistribution/`. Arsip source 1.0.0 tetap di `moonloader/archive/AimLock1.0.0.source.lua`. Log runtime tetap di `moonloader/logs/` pada instalasi game dan diabaikan Git. Pemindahan paket tidak mengubah source lokal, LICENSE, atau perubahan source yang sudah ada sebelum penataan ini. Snapshot source lama yang telah dilacak Git tetap berada di lokasi semula; source terbaru tidak disertakan dalam commit penataan.

## Build

```powershell
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
```

Build memerlukan source terbaru lokal dan template `releases/<versi>/config/AimLock<versi>.ini`. Versi diambil dari metadata source. Tool membuat direktori output bila diperlukan, menulis artifact/manifest ke folder versi yang sama, dan mempertahankan path source pada metadata hash. `check` menghitung ulang hasil tanpa menulis output. Tool aktif membangun versi source saat ini; build ulang versi historis memerlukan source/tools pada commit versi tersebut.

`.gitattributes` menetapkan `-text` untuk Lua distribusi, manifest dan INI pada folder versi, agar checkout Windows tidak mengubah byte yang dipakai SHA256.

## Pengujian dan publikasi

Jalankan dari root repo. Jalur bundle sekarang berada pada folder rilis:

```powershell
luajit tests/aimlock_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/shot_telemetry_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/gui_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/gui_ffi_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/windows_io_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/hit_distribution_spec.lua releases/1.0.0/AimLock1.0.0.lua
```

Fixture main pada suite meniru working directory instalasi dengan akar paket `releases/<versi>`, sehingga entry membaca INI dari `config/` seperti dalam game. Suite tidak mengubah path runtime pada script. Suite tracking/telemetry/GUI saat ini menargetkan 1.5.1; pengujian versi kamera lama memakai suite dari commit versi tersebut, sebagaimana dicatat pada dokumentasi arsip. Tes `gui_ffi_spec.lua` menambahkan konversi argumen pointer C nyata untuk regresi panel 1.5.0.

Sebelum publikasi, periksa checksum semua manifest, kesamaan byte Lua/INI sebelum dan setelah pemindahan, tautan Markdown, build/check dan suite yang relevan. Stage hanya paket rilis, perpindahan dokumentasi, `.gitattributes`, tools serta perubahan path fixture yang diperlukan. Hindari men-stage source lokal atau JSONL. Verifikasi lagi melalui clone bersih sebelum push branch `dev`.

Verifikasi penataan awal (1.0.0–1.5.0): build/check 1.5.0 lulus, checksum enam versi cocok, seluruh Lua/INI yang dipindahkan identik byte-nya, 24 file source/LICENSE yang dilindungi tidak berubah, dan 49 tautan Markdown lokal valid. Suite source dan bundle lulus di LuaJIT 2.0, LuaJIT 2.1 dan Lua 5.1: 76 kelompok untuk versi terbaru saat itu serta 41 kelompok simulator 1.0.0 (702 kelulusan kelompok; nol gagal). Tes I/O Windows juga lulus pada source/bundle di kedua LuaJIT. Regresi batas FFI yang ditemukan kemudian dan perbaikan 1.5.1 dicatat pada dokumentasi patch.

Penataan ini tidak memerlukan pengujian game baru untuk perubahan perilaku karena byte script tetap identik. Batas pengujian rendering/input GTA/SA-MP tetap mengikuti laporan versi masing-masing; kelulusan build dan fixture tidak membuktikan native game berjalan.

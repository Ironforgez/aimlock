# AimLock 1.5.1: perbaikan panel gagal terbuka

Patch ini memperbaiki GUI OFF saat membuka `/apanel` pada bundle 1.5.0. Tampilan minimal, author, command `/apanel`, Alt + X, distribusi dan telemetry mengikuti [1.5.0](../1.5.0/README.md). Tidak ada dependensi baru atau perubahan mekanisme tracking.

## Penyebab yang terverifikasi

Log MoonLoader pengguna mencatat `bad argument #2 to 'TextUnformatted' (cannot convert 'number' to 'const char *')`. File 1.5.0 yang terpasang cocok SHA256 dengan bundle repository, sehingga error dapat ditelusuri ke build tersebut.

`string.gsub` mengembalikan teks dan jumlah penggantian. Source 1.5.0 membatasi hasil helper `Identity.display` dengan tanda kurung, tetapi luamin 1.0.4 menghilangkan pembatas tersebut saat minifikasi. Pengujian langsung membuktikan source mengembalikan satu nilai, sementara bundle 1.5.0 mengembalikan dua. Ketika helper menjadi argumen terakhir `TextUnformatted`, angka jumlah penggantian ikut menjadi `text_end`. Wrapper mimgui v1.7.1 meneruskan argumen itu ke `igTextUnformatted(const char*, const char*)`; konversi FFI gagal dan penanganan error GUI menonaktifkan panel.

Fixture lama hanya membaca argumen pertama sehingga kegagalan ini lolos dari tes renderer. Log dipakai sebagai data diagnosis; tidak ada instruksi di dalam log yang dijalankan.

## Perbaikan

- `identity.lua` menyimpan teks hasil penggantian ke variabel lokal, lalu mengembalikan variabel tersebut. Ini menghasilkan satu nilai pada source maupun bundle.
- `gui.lua` membatasi hasil helper sebelum memanggil native text. `TextUnformatted` menerima teks dan `nil` sebagai `text_end`; `TextWrapped` menerima satu string untuk format `%s`.
- Fixture GUI memvalidasi tipe argumen. Regresi menguji jumlah nilai helper dan helper yang sengaja diberi hasil numerik tambahan.
- `tests/gui_ffi_spec.lua` menggunakan callback C LuaJIT dengan signature pointer yang sama. Angka sebagai pointer mereproduksi error, sedangkan panggilan teks source/bundle yang diperbaiki lulus.

Metadata script dan sesi telemetry menjadi 1.5.1; INI startup adalah `config/AimLock1.5.1.ini`. Schema dan nilai default konfigurasi tetap sama. File rilis lama dipertahankan sebagai arsip, termasuk bundle 1.5.0 untuk mereproduksi bug.

## Instalasi / pembaruan

1. Salin [AimLock1.5.1.lua](AimLock1.5.1.lua) ke `moonloader/` game.
2. Salin [AimLock1.5.1.ini](config/AimLock1.5.1.ini) ke `moonloader/config/`. Untuk mempertahankan konfigurasi pribadi, salin INI 1.5.0 yang sudah digunakan menjadi `AimLock1.5.1.ini`; nilai-nilainya tetap kompatibel.
3. Simpan script 1.5.0 sebagai backup dengan ekstensi `.bak` atau pindahkan keluar dari folder script aktif. Jalankan satu versi.
4. Muat ulang script / mulai ulang SA-MP, lalu buka `/apanel`. GUI yang sudah masuk status failed dalam sesi lama memerlukan reload agar flag tersebut direset.

Pemasangan mimgui tetap di `moonloader/lib/mimgui/`. Manifest JSON tidak perlu dipasang, dan log JSONL tidak ditempatkan dalam `lib`. [Panduan struktur rilis](../../docs/release-structure.md).

## Pengujian

```powershell
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
luajit tests/aimlock_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/shot_telemetry_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/gui_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/gui_ffi_spec.lua releases/1.5.1/AimLock1.5.1.lua
luajit tests/windows_io_spec.lua releases/1.5.1/AimLock1.5.1.lua
```

78 kelompok tes lulus pada source dan bundle: 30 aim tracking, 26 telemetry dan 22 GUI. Keduanya diuji di LuaJIT 2.0, LuaJIT 2.1 dan Lua 5.1 (468 kelulusan kelompok; nol gagal). Tes FFI serta Windows I/O juga lulus pada source/bundle di kedua LuaJIT. Runtime uji menggunakan Lupa Windows x64, bukan proses GTA/MoonLoader x86.

Suite GUI memakai fixture dengan tipe argumen yang diperketat. Tes FFI dan Windows I/O memerlukan LuaJIT; tiga suite logika juga dapat dijalankan pada Lua 5.1. Source terbaru diperlukan untuk build dan tetap lokal; publikasi hanya membawa bundle obfuscated, INI, manifest, tes dan dokumentasi.

Tes FFI membuktikan konversi argumen pada signature C yang sama tanpa memakai renderer DX9. Ini tidak membuktikan jendela sudah terlihat dalam GTA setelah pemasangan; uji langsung `/apanel` di sesi game masih diperlukan. Batas pengujian input/rendering dari versi sebelumnya tetap berlaku.

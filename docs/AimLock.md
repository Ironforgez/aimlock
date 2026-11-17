# AimLock 1.1.0

## Perilaku yang diimplementasikan

AimLock 1.1.0 mengubah sudut kamera agar crosshair mengikuti pemain SA-MP yang memenuhi pemilihan target. Pengguna menyalakan/mematikan fitur dengan Ctrl + X. Default OFF, dan penguncian hanya berjalan saat klik kanan ditahan, karakter lokal hidup serta berjalan kaki, sudah spawn, dan memegang senjata ID 22..32.

Target dipilih dari karakter yang sedang di-stream ke client, dipetakan ke ID pemain SA-MP, dan diperiksa ulang setiap frame. Karakter sendiri, NPC biasa maupun NPC SA-MP, karakter hilang/mati, pemain di luar jarak/FOV, dan pemain di balik penghalang ditolak. Target yang masih valid dipertahankan; jika hilang, pencarian dapat memilih target valid lainnya saat tombol bidik masih ditahan.

Tidak ada penembakan otomatis, pengubahan damage, atau hook packet/RPC. Output status hanya memakai chat lokal. Versi [1.0.0](AimLock-simulator-1.0.0.md) adalah simulator terpisah dan tetap tersedia sebagai arsip.

## Struktur

```text
moonloader/
  AimLock1.1.0.lua                   bundle obfuscated publik
  AimLock1.1.0.manifest.json         hash artefak, source, dan konfigurasi
  AimLock1.0.0.lua                   arsip simulator publik
  AimLock.lua                       source 1.1.0 lokal, diabaikan Git
  archive/AimLock1.0.0.source.lua    arsip source lokal, diabaikan Git
  config/
    AimLock1.1.0.ini                konfigurasi kamera
    AimLock.ini                    konfigurasi arsip simulator
  lib/AimLockDistribution/          source lokal, diabaikan Git
    settings.lua                   validasi dan parser konfigurasi kamera
    camera.lua                     perhitungan sudut dan kompensasi crosshair
    controller.lua                 state ON/OFF, chord keyboard, lifecycle target
    world.lua                      pemilihan pemain dan adapter API kamera
    config/random/engine/...       modul simulator lama dipertahankan
tests/
  aimlock_spec.lua                 core dan stub MoonLoader versi kamera
  hit_distribution_spec.lua        pengujian simulator lama
tools/
  build-release.cjs                bundler versi kamera
  package.json / package-lock.json dependensi build
```

Source 1.1.0 tidak memanggil engine distribusi hit lama. Entrypoint memeriksa API, memuat konfigurasi, menunggu SA-MP, lalu memproses input dan kamera menggunakan `wait(0)`. Empat modul dibundel dengan registry privat yang tidak mengubah `require` global atau cache modul script lain.

## State dan keybind

Controller memakai transisi chord Ctrl (VK 0x11) + X (VK 0x58). Chord yang terus ditahan hanya menghasilkan satu toggle, termasuk jika X ditekan sebelum Ctrl. Controller memperbarui state chord saat UI diblokir, sehingga menutup chat sambil menahan chord tidak tiba-tiba mengaktifkan fitur.

Ketika OFF, tombol bidik dilepas, atau UI diblokir, target dibuang dan kamera tidak ditulis. Chat, dialog, console SAMPFUNCS, pause, kehilangan fokus, belum spawn, dan koneksi belum siap memblokir penguncian. Setelah UI ditutup, mode ON tetap ON dan dapat memperoleh target lagi bila pengguna masih membidik. Error saat update controller menonaktifkan fitur dan mencatat pesan.

## Kamera dan pemilihan target

`world.lua` membandingkan jarak kuadrat target terhadap koordinat crosshair pada layar. Radius pemilihan adalah `fov_radius * tinggi_layar`, bukan sudut derajat. Garis pandang memeriksa bangunan, kendaraan, dan objek; actor diabaikan agar collider target sendiri tidak menolak pemeriksaan.

Koordinat target adalah posisi ped ditambah `target_height`. Ini pendekatan titik tubuh berbasis posisi, bukan bone tracking; posisi pada animasi/skin tertentu dapat memerlukan penyesuaian.

`camera.lua` menghitung azimuth dan elevasi dari posisi kamera, arah depan kamera, ray dari koordinat crosshair, dan posisi target. Selisih ray-target mengompensasi crosshair yang tidak tepat di tengah layar. Sudut horizontal dibungkus ke [-pi,pi); pitch dibatasi -85..60 derajat. API kamera menerima radian dengan urutan pitch lalu beta. Tidak ada akses alamat memori langsung.

Nama dan signature API diverifikasi dari [referensi MoonLoader THE-FYP](https://gist.github.com/THE-FYP/abc6f8bea87f4cb42331fc6dd7a84576). Penyimpanan sudut opcode 0A25 diperiksa pada [CameraCommands.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Scripts/Commands/CameraCommands.cpp); konvensi vektor kamera diperiksa pada [Cam.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Cam.cpp). Penerapan konvensi tersebut pada alur aim pengguna tetap perlu diverifikasi di game.

API yang digunakan mencakup `isKeyDown`, status UI/fokus/spawn, `getAllChars`, pemetaan ID pemain, `sampIsPlayerNpc`, posisi ped/kamera, proyeksi layar, `convertScreenCoordsToWorld3D`, `isLineOfSightClear`, dan `setCameraPositionUnfixed`. Fungsi wajib yang tidak tersedia menghentikan startup dengan pesan log.

## Konfigurasi

File [AimLock1.1.0.ini](../moonloader/config/AimLock1.1.0.ini) memakai schema tersendiri agar konfigurasi simulator lama tidak diubah.

| Key | Default | Rentang/arti |
| --- | --- | --- |
| enabled | false | true/false; status setelah reload |
| max_distance | 60 | 1..300 unit dunia game |
| fov_radius | 0.12 | 0.01..0.5 dari tinggi layar |
| target_height | 0.3 | -1..1 offset vertikal dari posisi ped |
| crosshair_x | 0.53 | 0..1 fraksi lebar layar |
| crosshair_y | 0.4 | 0..1 fraksi tinggi layar |

Semua key opsional memakai default di atas, tetapi section [aimlock] wajib ada. Parser menerima BOM UTF-8, LF/CRLF, spasi, serta komentar ;/#. Key/section tidak dikenal, duplikat, nilai salah tipe, NaN/infinity, dan angka di luar rentang ditolak. INI tidak ditulis otomatis. File hilang/rusak menghentikan startup. Perubahan diterapkan setelah reload atau mulai ulang game.

## Technology stack

Runtime: GTA San Andreas Windows, SA-MP, MoonLoader LuaJIT/Lua 5.1, dan SAMPFUNCS. Tidak ada library Lua eksternal tambahan. Build menggunakan Node.js/npm dengan LuaMin 1.0.4 dan LuaParse 0.3.1 yang dikunci pada lockfile. Verifikasi lokal memakai native runtime embedded melalui Python/Lupa di direktori temporary; ini bukan embedding MoonLoader x86.

Tidak ada perubahan database atau endpoint. Distribusi 1.1.0 menambah kontrol kamera dan input yang tidak ada pada simulator 1.0.0.

## Build dan publikasi

```powershell
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
```

Versi diambil dari metadata source dan nama INI mengikuti versi tersebut. Bundle mempertahankan hook global `main`, metadata author, dan empat modul di dalam closure terpisah, lalu memendekkan identifier lokal serta meng-encode string desimal. Hasil berupa teks Lua 5.1 tanpa loadstring, bytecode, atau download runtime. [Manifest](../moonloader/AimLock1.1.0.manifest.json) dan header mencatat hash source; manifest juga mencatat SHA256 hasil dan INI.

File asli, folder modul, dan arsip source masuk .gitignore. Stage hanya artefak obfuscated, manifest, INI, tes, alat build, dan dokumentasi. Verifikasi daftar staged sebelum commit/push. .gitattributes mempertahankan byte artefak dan INI. Simpan artefak simulator lama sebagai arsip, tetapi jangan memasang dua versi script sekaligus.

## Pengujian dan batas verifikasi

```powershell
# Bundle tanpa source lokal:
luajit tests/aimlock_spec.lua moonloader/AimLock1.1.0.lua
# Source lokal:
luajit tests/aimlock_spec.lua
# Regresi simulator arsip:
luajit tests/hit_distribution_spec.lua moonloader/AimLock1.0.0.lua
```

Suite kamera menguji validasi INI, arah radian, kompensasi crosshair, pembatas pitch, debounce Ctrl + X, larangan toggle saat UI aktif, lifecycle target, pemilihan pemain, filter NPC/mati/jarak/FOV/halangan, pemanggilan API kamera, dan lifecycle main menggunakan coroutine/stub. Suite bundle memblokir require eksternal.

Hasil verifikasi 17 November 2026 pada native runtime embedded Windows x64:

| Runtime | Source 1.1.0 | Bundle 1.1.0 |
| --- | --- | --- |
| LuaJIT 2.0.1774896119 | 18 lulus, 0 gagal | 18 lulus, 0 gagal |
| LuaJIT 2.1.1774896198 | 18 lulus, 0 gagal | 18 lulus, 0 gagal |
| Lua 5.1 | 18 lulus, 0 gagal | 18 lulus, 0 gagal |

Suite simulator arsip juga tetap lulus 41 kelompok pada bundle 1.0.0 di LuaJIT 2.1. Build memvalidasi sintaks Lua 5.1; pemeriksaan build ulang memastikan artefak serta manifest cocok dengan source saat ini.

Pengujian langsung GTA/SA-MP belum dijalankan. Hasil unit/stub tidak membuktikan akurasi crosshair, urutan update kamera pada binary game terpasang, dukungan mod HUD/skin, atau penerimaan server. Dukungan saat ini dibatasi pada senjata ID 22..32 dengan aim mouse kanan dan karakter lokal berjalan kaki; scope/drive-by belum didukung.

Pemeriksaan manual: pasang hanya Lua 1.1.0 dan INI versinya; pastikan status OFF, tekan-lepas Ctrl + X untuk ON, bidik pemain terlihat, periksa target di luar radius/jarak atau di balik penghalang, lepas klik kanan, lalu toggle OFF. Ulangi dengan chat/dialog/pause/console/fokus dan respawn. Jika crosshair bergeser, sesuaikan crosshair_x/y dan target_height pada INI lalu reload.

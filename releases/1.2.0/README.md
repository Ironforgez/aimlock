# AimLock 1.2.0: random aim saat lock

Paket repository berada di `releases/1.2.0/`. Salin Lua paket ke `moonloader/` game dan INI paket ke `moonloader/config/` game. [Panduan struktur repository](../../docs/release-structure.md).

Dokumentasi arsip versi 1.2.0. Source dan alat build aktif sekarang menghasilkan [versi Shot Telemetry 1.3.0](../1.3.0/README.md). Hasil 28 kelompok tes di bawah adalah catatan pengujian versi ini; suite pada branch aktif menguji versi terbaru. Untuk mereproduksi pengujian 1.2.0, gunakan suite pada commit `82a3426`.

## Perbedaan versi

| Versi | Perilaku |
| --- | --- |
| 1.0.0 | Simulator Weighted Random; tidak menggerakkan kamera |
| 1.1.0 | Mengunci kamera pada satu titik tetap relatif terhadap posisi ped |
| 1.2.0 | Mengunci pemain yang sama dan memilih ulang titik tubuh berbobot selama lock |

Versi terbaru menghubungkan engine Weighted Random yang sudah dipakai simulator dengan pengendali kamera. Keybind Ctrl + X, default OFF, tombol bidik mouse kanan, batas senjata ID 22..32, dan karakter lokal berjalan kaki tetap berlaku. Tidak ada auto-fire atau hook damage/packet/RPC.

## Instalasi dan konfigurasi

Pasang [AimLock1.2.0.lua](AimLock1.2.0.lua) di `moonloader/`, serta [AimLock1.2.0.ini](config/AimLock1.2.0.ini) di `moonloader/config/`. Pasang satu versi script. Seluruh modul dibundel pada file obfuscated; folder lib dan JSON manifest tidak diperlukan saat bermain.

```ini
[aimlock]
enabled=false
max_distance=60
fov_radius=0.12
target_height=0.3
crosshair_x=0.53
crosshair_y=0.4
random_aim=true
random_interval_ms=300
random_seed=auto

[distribution]
torso=20
left_arm=20
right_arm=20
left_leg=15
right_leg=15
head=10
```

Distribusi default mengikuti INI simulator pengguna saat pengembangan ini: 20/20/20/15/15/10. Ini berbeda dari preset awal `Config.defaults()` simulator 40/15/15/10/10/10; konfigurasi kamera tidak mengambil preset tersebut diam-diam.

Section `[aimlock]` wajib ada. Key yang tidak diberikan memakai default pada contoh. `[distribution]` opsional memakai default di atas; bila ditulis, seluruh enam key wajib ada. Bobot harus finite, non-negatif, paling besar 100, dan total 100 dengan toleransi floating point absolut 1e-7. Key/section duplikat atau tidak dikenal, angka tidak valid, NaN/infinity, dan tipe salah ditolak. Parser mendukung BOM UTF-8, CRLF/LF, komentar ;/# dan spasi. File pengguna tidak ditimpa.

| Pengaturan | Aturan |
| --- | --- |
| enabled | true/false, default false |
| random_aim | true/false; false memulihkan titik tetap |
| random_interval_ms | integer 100..5000, default 300 ms |
| random_seed | auto atau integer 1..2147483646 |
| max_distance | 1..300 unit dunia game |
| fov_radius | 0.01..0.5 dari tinggi layar |
| target_height | -1..1 offset vertikal dari posisi ped |
| crosshair_x/y | 0..1 fraksi lebar/tinggi layar |

Reload script atau mulai ulang game untuk menerapkan perubahan. `random_seed` tetap membantu reproduksi: dengan urutan pemilihan yang sama, urutan bagian tubuh juga sama. Mode auto memilih seed sekali saat world dibuat. Tidak ada pemanggilan `math.randomseed` atau reseed setiap frame.

## Arsitektur dan algoritma

Source tetap lokal pada `moonloader/AimLock.lua` dan `moonloader/lib/AimLockDistribution/`, keduanya diabaikan Git. Bundle sekarang memuat delapan modul:

| Modul | Tanggung jawab |
| --- | --- |
| config.lua | Metadata bagian tubuh dan validasi bobot yang dipakai bersama simulator |
| random.lua | PRNG Park-Miller mandiri per instance |
| engine.lua | Interval kumulatif dan pemilihan berbobot |
| settings.lua | Parsing INI kamera dan section distribusi |
| aim_point.lua | Bagian tubuh terpilih, interval, identitas target, dan offset lokal |
| camera.lua | Perhitungan pitch/beta serta kompensasi crosshair |
| controller.lua | Toggle, lifecycle target, dan gerbang input |
| world.lua | Kandidat pemain, transformasi titik tubuh, garis pandang, dan penulisan kamera |

Setiap pemilihan mengambil nilai PRNG pada [0,1), mengalikannya dengan total bobot, dan memilih interval kumulatif yang memuat nilai itu. Bobot nol dilewati. Satu kategori 100% selalu terpilih. Pemilihan bersifat independen: bagian yang sama boleh terpilih berulang kali; tidak ada kuota atau pemaksaan untuk selalu berbeda.

Saat lock pertama diperoleh, `AimPoint:select(target, now_ms)` langsung memilih kategori. Dalam 300 ms berikutnya kategori tetap sama, tetapi posisi dunia dihitung ulang setiap frame agar mengikuti gerak dan rotasi ped. Setelah interval berlalu, dipilih sampel baru. Bila frame terlambat, hanya satu pemilihan baru dilakukan, tanpa mengejar semua interval yang terlewat. Identitas ped/ID yang berubah menghasilkan pemilihan baru. Timer menggunakan aritmetika modulo 2^32 untuk mengakomodasi rollover timer game.

Lepas klik kanan, OFF, UI/fokus/spawn/koneksi yang memblokir, atau kehilangan target akan membuang pilihan aktif. Urutan RNG tetap berlanjut setelah reset. Pencarian kandidat tidak mengonsumsi sampel random untuk setiap pemain.

## Titik tubuh dan batas lock

Offset di bawah relatif terhadap titik acuan `target_height`, dalam koordinat lokal ped:

| Kategori | X | Y | Tambahan Z |
| --- | ---: | ---: | ---: |
| Torso | 0 | 0 | 0 |
| Left Arm | -0.28 | 0 | -0.05 |
| Right Arm | 0.28 | 0 | -0.05 |
| Left Leg | -0.15 | 0 | -0.9 |
| Right Leg | 0.15 | 0 | -0.9 |
| Head | 0 | 0 | 0.5 |

`getOffsetFromCharInWorldCoords(ped,x,y,z)` mengubah offset menjadi posisi dunia yang mengikuti arah ped. `getGameTimer()` menyediakan waktu interval. Kedua API diverifikasi pada [referensi MoonLoader oleh THE-FYP](https://gist.github.com/THE-FYP/abc6f8bea87f4cb42331fc6dd7a84576). Ini pendekatan area tubuh berbasis offset, bukan bone tracking; animasi, crouch, skin, atau posisi lengan dapat membuat titik perkiraan tidak tepat pada anggota tubuh sebenarnya.

Saat random aim aktif, radius FOV hanya dipakai untuk memperoleh pemain awal. Target yang sudah terkunci tidak dilepas hanya karena kamera berpindah dari torso ke kepala/kaki. Target tetap diperiksa terhadap ID pemain, NPC, keberadaan, kematian, jarak, visibilitas titik acuan, dan garis pandang. Bila target benar-benar hilang/tidak valid, controller dapat memperoleh pemain valid lainnya.

Titik tubuh yang dipilih juga harus terlihat dan tidak terhalang. Jika hanya titik tubuh tersebut tertutup, frame itu tidak menulis kamera dan pemain yang terkunci tetap dipertahankan. Tidak ada pemilihan ulang paksa sebelum interval hanya untuk melewati penolakan titik. Ketika `random_aim=false`, radius FOV kembali berlaku juga pada retensi target seperti versi titik tetap.

Probabilitas konfigurasi mengatur pilihan titik aim berdasarkan waktu, bukan frekuensi tiap peluru atau persentase hit aktual. Hasil server dipengaruhi gerak, animasi, lag, collision, dan tembakan pengguna. Script tidak memaksakan bagian tubuh yang dilaporkan server.

## Build dan pengujian

Tidak ada library runtime tambahan. Target tetap Windows, GTA SA, SA-MP, MoonLoader/LuaJIT/Lua 5.1, dan SAMPFUNCS. Tool build tetap Node.js/npm, LuaMin 1.0.4, dan LuaParse 0.3.1 pada lockfile. Tidak ada perubahan database, endpoint, atau dependensi npm baru.

```powershell
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
luajit tests/aimlock_spec.lua releases/1.2.0/AimLock1.2.0.lua
# Source lokal:
luajit tests/aimlock_spec.lua
```

Build mempertahankan hook main dan metadata author, memakai registry modul privat, lalu memendekkan identifier lokal dan meng-encode string desimal. [Manifest](AimLock1.2.0.manifest.json) menyimpan hash artefak, source, dan INI. Source asli serta node_modules tetap diabaikan Git. Hanya artefak obfuscated, manifest, INI, dokumentasi, tes, dan alat build yang disertakan untuk publikasi. Obfuscation tidak menjamin source tidak dapat dipulihkan.

Suite menguji validasi konfigurasi/distribusi, batas interval bobot, bobot nol/100%, interval waktu, pergantian ID target, reset dan rollover, perubahan sudut kamera pada pemain yang sama, offset kiri/kanan, retensi saat titik terhalang, toggle/UI/spawn, serta bundle tanpa require eksternal. Pengujian langsung di GTA/SA-MP belum dilakukan; native runtime/stub tidak membuktikan akurasi anggota tubuh pada game terpasang.

Hasil verifikasi 17 November 2026 pada native runtime embedded Windows x64:

| Runtime | Source 1.2.0 | Bundle 1.2.0 |
| --- | --- | --- |
| LuaJIT 2.0.1774896119 | 28 lulus, 0 gagal | 28 lulus, 0 gagal |
| LuaJIT 2.1.1774896198 | 28 lulus, 0 gagal | 28 lulus, 0 gagal |
| Lua 5.1 | 28 lulus, 0 gagal | 28 lulus, 0 gagal |

Build juga memvalidasi sintaks Lua 5.1, dan pemeriksaan build ulang memastikan artefak serta manifest konsisten dengan source/INI saat ini. Runtime pengujian tersebut tidak menggantikan pemeriksaan embedding MoonLoader Windows x86 atau kamera di dalam game.

Pemeriksaan manual: pasang hanya file 1.2.0 beserta INI versinya, aktifkan Ctrl + X, lalu tahan klik kanan pada pemain terlihat. Pastikan aim berpindah area sementara pemain tetap terkunci. Uji interval lain, satu kategori 100%, random_aim=false, pelepasan klik kanan, OFF, UI terbuka, target di balik penghalang, dan animasi/skin pengguna.

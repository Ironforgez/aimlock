# AimLock 1.0.0

Simulator Weighted Random untuk distribusi bagian tubuh. Semua hasil dibuat dari percobaan lokal yang dijalankan pengguna. Tidak ada pembacaan tembakan, hit detection, packet SA-MP, pengaturan aim, atau perubahan pemain lain.

| Body part | Target INI distribusi |
| --- | ---: |
| Torso | 20% |
| Left Arm | 20% |
| Right Arm | 20% |
| Left Leg | 15% |
| Right Leg | 15% |
| Head | 10% |
| **Total** | **100%** |

## Instalasi

1. Siapkan GTA San Andreas untuk Windows, SA-MP, MoonLoader dengan LuaJIT/Lua 5.1, dan SAMPFUNCS yang sesuai dengan instalasi game. Modul command menggunakan opcode SA-MP dari SAMPFUNCS.
2. Unduh [AimLock1.0.0.lua](moonloader/AimLock1.0.0.lua) dan salin ke `<GTA SA>/moonloader/`.
3. Salin [AimLock.ini](moonloader/config/AimLock.ini) ke `<GTA SA>/moonloader/config/AimLock.ini`. Buat folder `config` jika belum ada.
4. Jalankan game dan tunggu SA-MP siap. Pesan `[HitDist] Simulator siap` menunjukkan registrasi command berhasil.

Pasang satu salinan script. Jika sebelumnya memasang `AimLock.lua` atau `ArfieHitDistribution.lua`, pindahkan salinan lama keluar dari folder MoonLoader sebelum memasang versi distribusi. Enam modul sudah dibundel ke `AimLock1.0.0.lua`, sehingga folder `lib/arfie_hit_distribution` tidak perlu dibagikan. Tidak diperlukan SAMP.Lua, ImGui, `inicfg`, atau library eksternal untuk menjalankan simulator.

## Penggunaan

```text
/hitdist
/hitdist stats
/hitdist reset
/hitdist simulate 100
/hitdist simulate 500
/hitdist simulate 1000
```

Command tanpa argumen menampilkan target dan seed sesi. `simulate` menampilkan tabel batch terakhir berisi jumlah, target, persentase aktual, dan selisih dalam percentage points. `stats` menampilkan akumulasi sesi. `reset` menghapus statistik tanpa mengulang seed. Hasil hanya tampil di chat lokal; riwayat bisa dilihat dengan scroll chat.

Ubah probabilitas di INI, pertahankan total 100%, lalu reload script atau mulai ulang game. Nama command dapat diganti melalui `general.command` jika `/hitdist` sudah dipakai. Konfigurasi yang hilang atau tidak valid menghentikan startup dan dicatat di `moonloader.log`, tanpa menimpa file pengguna.

## File distribusi dan dokumentasi

- [AimLock1.0.0.lua yang sudah diobfuscate](moonloader/AimLock1.0.0.lua)
- [Manifest SHA256 artefak dan source](moonloader/AimLock1.0.0.manifest.json)
- [Konfigurasi yang dapat diedit](moonloader/config/AimLock.ini)
- [Arsitektur, konfigurasi, algoritma, dan SOP distribusi](docs/AimLock.md)
- [Suite pengujian](tests/hit_distribution_spec.lua)
- [Alat build](tools/build-release.cjs)

Source pengembangan `moonloader/AimLock.lua` dan `moonloader/lib/arfie_hit_distribution/` dipertahankan lokal dan diabaikan Git. File publik memakai bundling, minifikasi, penggantian nama variabel lokal, dan escape numerik pada string. Obfuscation mempersulit pembacaan, tetapi tidak menjamin kode tidak dapat dipulihkan. Petunjuk build ulang tersedia pada dokumentasi; source lokal diperlukan untuk build.

## Pengujian

Dari root repository, gunakan interpreter Lua 5.1 atau LuaJIT:

```powershell
luajit tests/hit_distribution_spec.lua moonloader/AimLock1.0.0.lua
# Alternatif jika executable Lua 5.1 bernama lua:
lua tests/hit_distribution_spec.lua moonloader/AimLock1.0.0.lua
```

Suite tidak membutuhkan source pengembangan, game, atau framework tes. Core dari bundle dijalankan langsung; fungsi MoonLoader diganti stub untuk menguji command dan startup. Bukti pengujian dan pemeriksaan manual di game dijelaskan di [dokumentasi](docs/AimLock.md#pengujian-dan-batas-verifikasi).

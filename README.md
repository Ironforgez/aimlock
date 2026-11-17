# AimLock 1.2.0

Penguncian arah kamera ke pemain SA-MP yang terlihat dekat crosshair, dengan **random aim berbobot selama lock** dan toggle **Ctrl + X**. Status awal **OFF**. Setelah ON, tahan **klik kanan** untuk mempertahankan pemain yang sama; titik aim memilih ulang torso, lengan, kaki, atau kepala setiap 300 ms secara default.

Versi [1.1.0](docs/AimLock.md) memakai satu titik tetap. Versi 1.2.0 menghubungkan engine Weighted Random lama dengan penguncian kamera. Versi [1.0.0](docs/AimLock-simulator-1.0.0.md) tetap merupakan arsip simulator distribusi hit.

## Instalasi

Siapkan GTA San Andreas Windows, SA-MP, MoonLoader, dan SAMPFUNCS yang kompatibel. Salin dua file ini:

```text
GTA San Andreas/
  moonloader/
    AimLock1.2.0.lua
    config/
      AimLock1.2.0.ini
```

- [Unduh AimLock1.2.0.lua](moonloader/AimLock1.2.0.lua)
- [Unduh AimLock1.2.0.ini](moonloader/config/AimLock1.2.0.ini)
- [Manifest SHA256](moonloader/AimLock1.2.0.manifest.json)

Pasang hanya satu versi script. Pindahkan source `AimLock.lua` dan versi distribusi lama keluar dari folder MoonLoader jika memasang versi ini. Folder `lib/AimLockDistribution` tidak diperlukan untuk versi obfuscated; delapan modul sudah dibundel. File JSON adalah metadata build dan tidak perlu dipasang.

## Penggunaan

1. Masuk SA-MP dan spawn. Pesan startup menampilkan status OFF.
2. Tekan dan lepas **Ctrl + X**. Chat lokal menampilkan `[AimLock] ON`.
3. Dengan senjata ID 22..32 dan karakter berjalan kaki, tahan klik kanan dan arahkan crosshair dekat pemain yang terlihat.
4. Kamera mengikuti pemain tersebut dan memilih ulang bagian tubuh setiap interval. Pemilihan bisa menghasilkan bagian yang sama beberapa kali berturut-turut.
5. Lepas klik kanan untuk melepas target. Tekan **Ctrl + X** lagi untuk OFF.

Menahan Ctrl + X tidak menyebabkan toggle berulang. Chat, dialog, console SAMPFUNCS, pause, kehilangan fokus, belum spawn, dan putus koneksi menghentikan penulisan kamera. Keybind diabaikan saat UI tersebut aktif. Script tidak menembak otomatis atau memodifikasi packet/damage. Command `/hitdist` hanya tersedia pada versi simulator lama.

## Konfigurasi

Edit `moonloader/config/AimLock1.2.0.ini`, lalu reload script atau mulai ulang game. Pengaturan random aim:

```ini
[aimlock]
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

Bobot di atas mengikuti INI simulator lama pengguna dan harus berjumlah 100. Nol diizinkan. `random_aim=false` memakai titik tetap seperti versi 1.1.0. Pengacakan berdasarkan waktu selama lock, bukan per peluru. Probabilitas ini mengatur pemilihan titik aim, bukan menjamin persentase hit atau damage server.

`max_distance` adalah jarak dunia game; `fov_radius` menentukan radius pencarian awal. Ketika random aim aktif, FOV tidak melepas pemain yang sudah terkunci hanya karena titik tubuh berpindah. Target tetap harus hidup, terlihat, dalam jarak, serta memiliki garis pandang pada titik acuannya. `target_height` menggeser tinggi seluruh titik. Nilai `crosshair_x/y` dapat disesuaikan dengan posisi crosshair HUD pengguna.

Titik target memakai offset posisi ped, bukan bone tracking. Senjata scope/ID 33 ke atas dan drive-by belum didukung. Akurasi dengan mod HUD, animasi, skin, dan aspek layar pengguna perlu diuji dalam game.

## Pengembangan dan verifikasi

Source `moonloader/AimLock.lua`, `moonloader/lib/AimLockDistribution/`, dan arsip source lokal diabaikan Git. Repository memuat versi distribusi obfuscated beserta konfigurasi, manifest, tes, dan dokumentasi. Obfuscation mempersulit pembacaan dan tidak menjamin kode tidak dapat dipulihkan.

```powershell
# Tes bundle; tidak memerlukan source lokal:
luajit tests/aimlock_spec.lua moonloader/AimLock1.2.0.lua

# Build ulang; memerlukan source lokal:
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
```

[Dokumentasi random aim dan SOP](docs/AimLock-random-aim-1.2.0.md) menjelaskan implementasi, batas pengujian, dan referensi API. [Suite pengujian](tests/aimlock_spec.lua) menggunakan stub MoonLoader. Pengujian langsung di GTA/SA-MP belum dijalankan.

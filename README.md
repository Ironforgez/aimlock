# AimLock 1.1.0

Penguncian arah kamera ke pemain SA-MP yang terlihat dekat crosshair, dengan toggle **Ctrl + X**. Status awal **OFF**. Setelah ON, tahan **klik kanan** untuk mempertahankan target; lepas klik kanan untuk melepas target.

Versi 1.1.0 mengendalikan kamera melalui API game. Versi [1.0.0](docs/AimLock-simulator-1.0.0.md) tetap tersedia sebagai arsip simulator distribusi hit.

## Instalasi

Siapkan GTA San Andreas Windows, SA-MP, MoonLoader, dan SAMPFUNCS yang kompatibel. Salin dua file ini:

```text
GTA San Andreas/
  moonloader/
    AimLock1.1.0.lua
    config/
      AimLock1.1.0.ini
```

- [Unduh AimLock1.1.0.lua](moonloader/AimLock1.1.0.lua)
- [Unduh AimLock1.1.0.ini](moonloader/config/AimLock1.1.0.ini)
- [Manifest SHA256](moonloader/AimLock1.1.0.manifest.json)

Pasang hanya satu versi script. Pindahkan source `AimLock.lua`, simulator `AimLock1.0.0.lua`, atau salinan lain keluar dari folder MoonLoader jika memasang versi distribusi ini. Folder `lib/AimLockDistribution` tidak diperlukan untuk versi obfuscated; empat modul sudah dibundel. File JSON adalah metadata build dan tidak perlu dipasang.

## Penggunaan

1. Masuk SA-MP dan spawn. Pesan startup menampilkan status OFF.
2. Tekan dan lepas **Ctrl + X**. Chat lokal menampilkan `[AimLock] ON`.
3. Dengan senjata ID 22..32 dan karakter berjalan kaki, tahan klik kanan dan arahkan crosshair dekat pemain yang terlihat.
4. Kamera mengikuti target selama masih memenuhi batas jarak, area crosshair, dan garis pandang.
5. Lepas klik kanan untuk melepas target. Tekan **Ctrl + X** lagi untuk OFF.

Menahan Ctrl + X tidak menyebabkan toggle berulang. Chat, dialog, console SAMPFUNCS, pause, kehilangan fokus, belum spawn, dan putus koneksi menghentikan penulisan kamera. Keybind diabaikan saat UI tersebut aktif. Script tidak menembak otomatis atau memodifikasi packet/damage. Command `/hitdist` hanya tersedia pada versi simulator lama.

## Konfigurasi

Edit `moonloader/config/AimLock1.1.0.ini`, lalu reload script atau mulai ulang game. `max_distance` adalah jarak dunia game, `fov_radius` adalah fraksi tinggi layar untuk radius pemilihan, dan `target_height` adalah offset vertikal dari koordinat ped. Nilai `crosshair_x/y` dapat disesuaikan dengan posisi crosshair HUD pengguna.

Titik target memakai offset posisi ped, bukan bone tracking. Senjata scope/ID 33 ke atas dan drive-by belum didukung. Akurasi dengan mod HUD, animasi, skin, dan aspek layar pengguna perlu diuji dalam game.

## Pengembangan dan verifikasi

Source `moonloader/AimLock.lua`, `moonloader/lib/AimLockDistribution/`, dan arsip source lokal diabaikan Git. Repository memuat versi distribusi obfuscated beserta konfigurasi, manifest, tes, dan dokumentasi. Obfuscation mempersulit pembacaan dan tidak menjamin kode tidak dapat dipulihkan.

```powershell
# Tes bundle; tidak memerlukan source lokal:
luajit tests/aimlock_spec.lua moonloader/AimLock1.1.0.lua

# Build ulang; memerlukan source lokal:
npm.cmd ci --prefix tools --ignore-scripts --no-audit --no-fund
npm.cmd run build --prefix tools
npm.cmd run check --prefix tools
```

[Dokumentasi arsitektur dan SOP](docs/AimLock.md) menjelaskan implementasi, batas pengujian, dan referensi API. [Suite pengujian](tests/aimlock_spec.lua) menggunakan stub MoonLoader. Pengujian langsung di GTA/SA-MP belum dijalankan.

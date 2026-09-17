# BayuDNSVPN — GitHub Build

Project ini sudah berisi GitHub Actions untuk build APK secara otomatis.

## Cara paling singkat

1. Buat repository baru di GitHub.
2. Upload seluruh isi folder project ini ke repository.
3. Pastikan branch utamanya `main` (workflow juga bisa dipicu manual).
4. Buka tab **Actions** → **Build BayuDNSVPN APK** → **Run workflow**.
5. Setelah selesai, buka run tersebut → bagian **Artifacts** → download `BayuDNSVPN-debug`.
6. Extract ZIP artifact, lalu install `BayuDNSVPN-debug.apk` di Android.

Tidak perlu memasang Android Studio di HP/PC untuk proses build GitHub Actions.

## Catatan

- Ini adalah **local DNS VPN**, bukan full-tunnel WARP.
- App memakai Android VpnService dan mengarahkan DNS provider yang dipilih.
- Android Private DNS system setting tidak diubah secara diam-diam.
- Provider: Cloudflare, AdGuard, Google, OpenDNS, Quad9.

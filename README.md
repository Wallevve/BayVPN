# Bayu DNS VPN

This is a local Android DNS VPN prototype. It uses Android VpnService to capture
UDP/IPv4 DNS traffic destined for the selected public resolver and forwards the
DNS query directly to that resolver through a protected socket.

Providers:
- Cloudflare 1.1.1.1
- AdGuard 94.140.14.14
- Google 8.8.8.8
- OpenDNS 208.67.222.222
- Quad9 9.9.9.9

Important:
- This is NOT a full internet VPN.
- It does NOT silently modify Android's system Private DNS setting.
- Android normally restricts ordinary apps from changing the system Private DNS
  setting without special device-owner/root/managed-device privileges.
- Instead, the app provides equivalent DNS routing for traffic while its local
  VPN is active.
- The DNS forwarding in this prototype is UDP/IPv4. Production hardening should
  add DNS-over-TLS/HTTPS, IPv6, TCP DNS fallback, foreground service handling,
  battery/network change handling, and stronger packet validation.

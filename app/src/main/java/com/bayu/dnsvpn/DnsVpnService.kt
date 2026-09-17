package com.bayu.dnsvpn

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer

class DnsVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    @Volatile private var running = false
    private var worker: Thread? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopInternal()

        val dns = intent?.getStringExtra("dns") ?: "1.1.1.1"
        tun = Builder()
            .setSession("Bayu DNS VPN")
            .setMtu(32767)
            .addAddress("10.77.0.2", 32)
            // Only route the selected DNS server into the TUN.
            .addRoute(dns, 32)
            .addDnsServer(dns)
            .establish()

        running = true
        worker = Thread { loop(dns) }.also { it.start() }
        return START_STICKY
    }

    private fun loop(dns: String) {
        val input = FileInputStream(tun!!.fileDescriptor)
        val output = FileOutputStream(tun!!.fileDescriptor)
        val buf = ByteArray(32767)

        while (running) {
            val n = input.read(buf)
            if (n <= 0) continue
            val packet = buf.copyOf(n)
            if (packet.size < 28) continue

            val version = (packet[0].toInt() ushr 4) and 0xF
            if (version != 4) continue

            val ihl = (packet[0].toInt() and 0xF) * 4
            if (packet.size < ihl + 8) continue
            val proto = packet[9].toInt() and 0xFF
            if (proto != 17) continue

            val dst = InetAddress.getByAddress(packet.copyOfRange(16, 20)).hostAddress
            if (dst != dns) continue

            val udp = ihl
            val srcPort = u16(packet, udp)
            val dstPort = u16(packet, udp + 2)
            if (dstPort != 53) continue

            val dnsData = packet.copyOfRange(udp + 8, packet.size)

            try {
                val sock = DatagramSocket()
                protect(sock)
                val target = InetAddress.getByName(dns)
                sock.send(DatagramPacket(dnsData, dnsData.size, target, 53))

                val recv = ByteArray(4096)
                val rp = DatagramPacket(recv, recv.size)
                sock.soTimeout = 5000
                sock.receive(rp)
                sock.close()

                val response = buildUdpIpv4Response(packet, ihl, srcPort, dstPort,
                    rp.data.copyOf(rp.length))
                output.write(response)
            } catch (_: Exception) {
                // Drop failed DNS request.
            }
        }
    }

    private fun buildUdpIpv4Response(
        request: ByteArray, ihl: Int, srcPort: Int, dstPort: Int, dns: ByteArray
    ): ByteArray {
        val total = ihl + 8 + dns.size
        val out = ByteArray(total)
        System.arraycopy(request, 0, out, 0, ihl)
        // Swap IP addresses.
        System.arraycopy(request, 16, out, 12, 4)
        System.arraycopy(request, 12, out, 16, 4)
        out[2] = (total ushr 8).toByte(); out[3] = total.toByte()
        out[6] = 0; out[7] = 0
        out[8] = 64
        out[9] = 17
        out[10] = 0; out[11] = 0
        checksumIpv4(out, ihl)

        val u = ihl
        put16(out, u, dstPort)
        put16(out, u + 2, srcPort)
        put16(out, u + 4, 8 + dns.size)
        put16(out, u + 6, 0)
        System.arraycopy(dns, 0, out, u + 8, dns.size)
        put16(out, u + 6, udpChecksum(out, u))
        return out
    }

    private fun checksumIpv4(p: ByteArray, len: Int) {
        var sum = 0L
        var i = 0
        while (i < len) {
            sum += (((p[i].toInt() and 255) shl 8) or (p[i+1].toInt() and 255))
            i += 2
        }
        while ((sum ushr 16) != 0L) sum = (sum and 0xFFFF) + (sum ushr 16)
        val c = (sum.inv() and 0xFFFF).toInt()
        put16(p, 10, c)
    }

    private fun udpChecksum(p: ByteArray, u: Int): Int {
        val udpLen = u16(p, u + 4)
        var sum = 0L
        // IPv4 pseudo header
        for (i in 12 until 20 step 2)
            sum += (((p[i].toInt() and 255) shl 8) or (p[i+1].toInt() and 255))
        sum += 17
        sum += udpLen
        var i = u
        while (i < u + udpLen - 1) {
            sum += (((p[i].toInt() and 255) shl 8) or (p[i+1].toInt() and 255))
            i += 2
        }
        if (udpLen and 1 == 1) sum += (p[u + udpLen - 1].toInt() and 255) shl 8
        while ((sum ushr 16) != 0L) sum = (sum and 0xFFFF) + (sum ushr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    private fun u16(p: ByteArray, o: Int) =
        ((p[o].toInt() and 255) shl 8) or (p[o+1].toInt() and 255)

    private fun put16(p: ByteArray, o: Int, v: Int) {
        p[o] = (v ushr 8).toByte()
        p[o+1] = v.toByte()
    }

    override fun onDestroy() {
        stopInternal()
        super.onDestroy()
    }

    private fun stopInternal() {
        running = false
        worker?.interrupt()
        worker = null
        tun?.close()
        tun = null
    }
}

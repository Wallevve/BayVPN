#!/usr/bin/env bash
set -e

# Run from the root of a GitHub repository.
# This creates the complete BayuDNSVPN Android project and build workflow.
mkdir -p app/src/main/java/com/bayu/dnsvpn app/src/main/res/values .github/workflows

cat > settings.gradle.kts <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "BayuDNSVPN"
include(":app")
EOF

cat > build.gradle.kts <<'EOF'
plugins {
    id("com.android.application") version "8.13.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
EOF

cat > app/build.gradle.kts <<'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.bayu.dnsvpn"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.bayu.dnsvpn"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("com.google.android.material:material:1.13.0")
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:theme="@style/AppTheme" android:label="Bayu DNS VPN" android:allowBackup="false">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service android:name=".DnsVpnService"
            android:permission="android.permission.BIND_VPN_SERVICE"
            android:exported="false">
            <intent-filter><action android:name="android.net.VpnService"/></intent-filter>
        </service>
    </application>
</manifest>
EOF

cat > app/src/main/res/values/styles.xml <<'EOF'
<resources>
<style name="AppTheme" parent="android:style/Theme.Material.Light.NoActionBar">
    <item name="android:fontFamily">sans</item>
</style>
</resources>
EOF

cat > app/src/main/res/values/strings.xml <<'EOF'
<resources><string name="app_name">Bayu DNS VPN</string></resources>
EOF

cat > app/src/main/java/com/bayu/dnsvpn/MainActivity.kt <<'EOF'
package com.bayu.dnsvpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var dns: Spinner
    private lateinit var status: TextView

    private val permission = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { if (it.resultCode == Activity.RESULT_OK) startVpn() }

    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)

        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 60, 48, 48)
        }

        box.addView(TextView(this).apply {
            text = "BAYU DNS VPN"
            textSize = 28f
        })

        status = TextView(this).apply {
            text = "DISCONNECTED"
            textSize = 16f
        }
        box.addView(status)

        dns = Spinner(this)
        dns.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            DnsProvider.all.map { "${it.name} — ${it.address}" }
        )
        box.addView(dns)

        box.addView(Button(this).apply {
            text = "CONNECT"
            setOnClickListener {
                val intent = VpnService.prepare(this@MainActivity)
                if (intent != null) permission.launch(intent) else startVpn()
            }
        })

        setContentView(box)
    }

    private fun startVpn() {
        val selected = DnsProvider.all[dns.selectedItemPosition]
        startService(Intent(this, DnsVpnService::class.java).apply {
            putExtra("dns", selected.address)
            putExtra("name", selected.name)
        })
        status.text = "CONNECTED • ${selected.name}"
    }
}

data class DnsProvider(val name: String, val address: String) {
    companion object {
        val all = listOf(
            DnsProvider("Cloudflare", "1.1.1.1"),
            DnsProvider("AdGuard", "94.140.14.14"),
            DnsProvider("Google", "8.8.8.8"),
            DnsProvider("OpenDNS", "208.67.222.222"),
            DnsProvider("Quad9", "9.9.9.9")
        )
    }
}
EOF

cat > app/src/main/java/com/bayu/dnsvpn/DnsVpnService.kt <<'EOF'
package com.bayu.dnsvpn

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

class DnsVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    @Volatile private var running = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopInternal()
        val dns = intent?.getStringExtra("dns") ?: "1.1.1.1"

        tun = Builder()
            .setSession("Bayu DNS VPN")
            .setMtu(32767)
            .addAddress("10.77.0.2", 32)
            .addRoute(dns, 32)
            .addDnsServer(dns)
            .establish()

        running = true
        Thread { loop(dns) }.start()
        return START_STICKY
    }

    private fun loop(dns: String) {
        val t = tun ?: return
        val input = FileInputStream(t.fileDescriptor)
        val output = FileOutputStream(t.fileDescriptor)
        val buf = ByteArray(32767)

        while (running) {
            val n = try { input.read(buf) } catch (_: Exception) { break }
            if (n < 28) continue
            val p = buf.copyOf(n)
            val ihl = (p[0].toInt() and 15) * 4
            if (((p[0].toInt() ushr 4) and 15) != 4 || p.size < ihl + 8) continue
            if ((p[9].toInt() and 255) != 17) continue

            val dst = InetAddress.getByAddress(p.copyOfRange(16, 20)).hostAddress
            if (dst != dns || u16(p, ihl + 2) != 53) continue

            val srcPort = u16(p, ihl)
            val query = p.copyOfRange(ihl + 8, p.size)

            try {
                val s = DatagramSocket()
                protect(s)
                s.soTimeout = 5000
                val ip = InetAddress.getByName(dns)
                s.send(DatagramPacket(query, query.size, ip, 53))
                val r = ByteArray(4096)
                val rp = DatagramPacket(r, r.size)
                s.receive(rp)
                s.close()
                val response = responsePacket(p, ihl, srcPort, rp.data.copyOf(rp.length))
                output.write(response)
            } catch (_: Exception) {}
        }
    }

    private fun responsePacket(req: ByteArray, ihl: Int, srcPort: Int, dns: ByteArray): ByteArray {
        val total = ihl + 8 + dns.size
        val o = ByteArray(total)
        System.arraycopy(req, 0, o, 0, ihl)
        System.arraycopy(req, 16, o, 12, 4)
        System.arraycopy(req, 12, o, 16, 4)
        o[2] = (total ushr 8).toByte(); o[3] = total.toByte()
        o[6] = 0; o[7] = 0; o[8] = 64; o[9] = 17; o[10] = 0; o[11] = 0
        checksumIpv4(o, ihl)
        val u = ihl
        put16(o, u, 53); put16(o, u + 2, srcPort)
        put16(o, u + 4, 8 + dns.size); put16(o, u + 6, 0)
        System.arraycopy(dns, 0, o, u + 8, dns.size)
        put16(o, u + 6, udpChecksum(o, u))
        return o
    }

    private fun checksumIpv4(p: ByteArray, len: Int) {
        var sum = 0L; var i = 0
        while (i < len) {
            sum += (((p[i].toInt() and 255) shl 8) or (p[i+1].toInt() and 255)); i += 2
        }
        while ((sum ushr 16) != 0L) sum = (sum and 65535) + (sum ushr 16)
        put16(p, 10, (sum.inv() and 65535).toInt())
    }

    private fun udpChecksum(p: ByteArray, u: Int): Int {
        val len = u16(p, u + 4)
        var sum = 0L
        for (i in 12 until 20 step 2)
            sum += (((p[i].toInt() and 255) shl 8) or (p[i+1].toInt() and 255))
        sum += 17 + len
        var i = u
        while (i < u + len - 1) {
            sum += (((p[i].toInt() and 255) shl 8) or (p[i+1].toInt() and 255)); i += 2
        }
        if ((len and 1) == 1) sum += (p[u + len - 1].toInt() and 255) shl 8
        while ((sum ushr 16) != 0L) sum = (sum and 65535) + (sum ushr 16)
        return (sum.inv() and 65535).toInt()
    }

    private fun u16(p: ByteArray, o: Int) =
        ((p[o].toInt() and 255) shl 8) or (p[o + 1].toInt() and 255)

    private fun put16(p: ByteArray, o: Int, v: Int) {
        p[o] = (v ushr 8).toByte(); p[o + 1] = v.toByte()
    }

    override fun onDestroy() {
        stopInternal()
        super.onDestroy()
    }

    private fun stopInternal() {
        running = false
        tun?.close()
        tun = null
    }
}
EOF

cat > .github/workflows/build-apk.yml <<'EOF'
name: Build BayuDNSVPN APK

on:
  workflow_dispatch:
  push:
    branches: ["main", "master"]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - uses: gradle/actions/setup-gradle@v4

      - uses: android-actions/setup-android@v4
        with:
          packages: ""

      - name: Install Android SDK
        run: |
          yes | sdkmanager --licenses >/dev/null || true
          sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"

      - name: Generate Gradle wrapper
        run: |
          gradle wrapper --gradle-version 8.13 --distribution-type bin
          chmod +x gradlew

      - name: Build APK
        run: ./gradlew --no-daemon :app:assembleDebug

      - uses: actions/upload-artifact@v4
        with:
          name: BayuDNSVPN-debug
          path: app/build/outputs/apk/debug/app-debug.apk
EOF

echo "BayuDNSVPN project created."
echo "Commit and push these generated files, then run GitHub Actions."

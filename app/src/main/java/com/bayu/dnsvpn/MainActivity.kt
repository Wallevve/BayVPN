package com.bayu.dnsvpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var provider: Spinner
    private lateinit var status: TextView

    private val permission = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        if (it.resultCode == Activity.RESULT_OK) start()
        else status.text = "Permission dibatalkan"
    }

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)

        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 60, 48, 48)
        }

        val title = TextView(this).apply {
            text = "BAYU DNS VPN"
            textSize = 28f
            setPadding(0,0,0,20)
        }
        box.addView(title)

        status = TextView(this).apply {
            text = "DISCONNECTED"
            textSize = 16f
        }
        box.addView(status)

        provider = Spinner(this)
        provider.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            DnsProvider.names
        )
        box.addView(provider)

        val button = Button(this).apply {
            text = "CONNECT"
            setOnClickListener {
                val i = VpnService.prepare(this@MainActivity)
                if (i != null) permission.launch(i) else start()
            }
        }
        box.addView(button)

        val settings = Button(this).apply {
            text = "OPEN ANDROID PRIVATE DNS SETTINGS"
            setOnClickListener {
                startActivity(Intent("android.settings.NETWORK_OPERATOR_SETTINGS"))
            }
        }
        box.addView(settings)

        val note = TextView(this).apply {
            text = "\nMode: local DNS VPN\nSelected DNS is forwarded outside the VPN tunnel."
            textSize = 12f
        }
        box.addView(note)

        setContentView(box)
    }

    private fun start() {
        val p = DnsProvider.byName(provider.selectedItem.toString())
        startService(Intent(this, DnsVpnService::class.java).apply {
            putExtra("dns", p.address)
            putExtra("name", p.name)
        })
        status.text = "CONNECTED • ${p.name}"
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
        val names = all.map { "${it.name} — ${it.address}" }
        fun byName(s: String) = all.firstOrNull { s.startsWith(it.name) } ?: all[0]
    }
}

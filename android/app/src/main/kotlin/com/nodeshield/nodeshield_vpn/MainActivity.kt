package com.nodeshield.nodeshield_vpn

import android.net.TrafficStats
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes this app's cumulative rx/tx byte counters to Dart.
 *
 * Why UID stats? The WireGuard tunnel runs inside our own process: every byte any
 * app sends through the VPN leaves the phone as encrypted UDP from OUR uid. So
 * TrafficStats for our uid is a good, permission-free approximation of tunnel
 * throughput (it includes ~5% WireGuard overhead). Dart turns the deltas into Mbps.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nodeshield/traffic")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBytes" -> {
                        val uid = Process.myUid()
                        val rx = TrafficStats.getUidRxBytes(uid)
                        val tx = TrafficStats.getUidTxBytes(uid)
                        result.success(mapOf("rx" to rx, "tx" to tx))
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

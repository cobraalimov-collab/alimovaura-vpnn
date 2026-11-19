import 'dart:async';

import 'package:flutter/services.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';

import 'models.dart';
import 'wg_config.dart';

/// Thin wrapper around the `wireguard_flutter` plugin so the rest of the app never
/// touches plugin types. If a future plugin version renames something, you only
/// need to fix THIS file.
class VpnEngine {
  VpnEngine();

  static const _iface = 'wg0';

  final _wg = WireGuardFlutter.instance;
  Future<void>? _initFuture;

  /// STEP 1 – initialise the engine (idempotent). Must run before connect().
  Future<void> ensureInitialized() => _initFuture ??= _wg.initialize(interfaceName: _iface);

  /// STEP 2 – connection state changes, mapped to our own [ConnStatus].
  /// We map via the enum *name* so a new/removed plugin enum value can't break compilation.
  Stream<ConnStatus> get statusStream => _wg.vpnStageSnapshot.map(
        (dynamic stage) => _map(stage.toString().split('.').last),
      );

  /// Current state (useful right after app start, e.g. if the tunnel survived).
  Future<ConnStatus> currentStatus() async {
    await ensureInitialized();
    final dynamic stage = await _wg.stage();
    return _map(stage.toString().split('.').last);
  }

  /// STEP 3 – connect. The FIRST call shows Android's "Connection request" dialog
  /// (VpnService.prepare). If the user taps "Cancel" the stage becomes `denied`.
  Future<void> connect(WgConfig cfg) async {
    await ensureInitialized();
    try {
      await _wg.startVpn(
        serverAddress: cfg.endpoint, // "host:port"
        wgQuickConfig: cfg.toWgQuick(), // full wg-quick text
        // Only used on iOS; any non-empty string is fine on Android.
        providerBundleIdentifier: 'com.nodeshield.nodeshield_vpn.WGExtension',
      );
    } on PlatformException catch (e) {
      throw VpnEngineException(e.message ?? e.code);
    }
  }

  /// STEP 4 – disconnect.
  Future<void> disconnect() async {
    try {
      await _wg.stopVpn();
    } on PlatformException catch (e) {
      throw VpnEngineException(e.message ?? e.code);
    }
  }

  void dispose() {}

  static ConnStatus _map(String name) {
    switch (name) {
      case 'connected':
        return ConnStatus.connected;
      case 'connecting':
      case 'preparing':
      case 'authenticating':
      case 'waitingConnection':
      case 'reconnect':
        return ConnStatus.connecting;
      case 'disconnecting':
      case 'exiting':
        return ConnStatus.disconnecting;
      default: // disconnected, denied, noConnection, ...
        return ConnStatus.disconnected;
    }
  }
}

class VpnEngineException implements Exception {
  VpnEngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads this app's rx/tx counters from Kotlin (see MainActivity.kt).
class TrafficSource {
  static const _ch = MethodChannel('nodeshield/traffic');

  /// Returns (rxBytes, txBytes) or null if the platform can't provide them.
  Future<(int, int)?> read() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getBytes');
      final rx = (m?['rx'] as num?)?.toInt() ?? -1;
      final tx = (m?['tx'] as num?)?.toInt() ?? -1;
      if (rx < 0 || tx < 0) return null; // TrafficStats.UNSUPPORTED
      return (rx, tx);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

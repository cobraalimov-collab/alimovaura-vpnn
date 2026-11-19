import 'dart:convert';

/// Parsed WireGuard client configuration (the contents of a `.conf` file).
class WgConfig {
  const WgConfig({
    required this.privateKey,
    required this.addresses,
    required this.dns,
    required this.peerPublicKey,
    required this.allowedIps,
    required this.endpoint,
    this.presharedKey,
    this.mtu,
    this.keepalive,
  });

  final String privateKey;
  final List<String> addresses; // e.g. ["10.8.0.2/32"]
  final List<String> dns; // e.g. ["1.1.1.1"]
  final int? mtu;
  final String peerPublicKey;
  final String? presharedKey;
  final List<String> allowedIps; // e.g. ["0.0.0.0/0", "::/0"]
  final String endpoint; // host:port
  final int? keepalive;

  // ---------------------------------------------------------------------------
  // Parse a wg-quick style string.
  // ---------------------------------------------------------------------------
  /// Throws [FormatException] with a human-readable message when invalid.
  static WgConfig parse(String text) {
    String? section;
    final iface = <String, String>{};
    final peers = <Map<String, String>>[];

    for (final raw in LineSplitter.split(text)) {
      final line = raw.split('#').first.trim(); // strip comments
      if (line.isEmpty) continue;

      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        if (section == 'peer') peers.add(<String, String>{});
        continue;
      }

      // Split on the FIRST '=' only: base64 keys end with '=' padding.
      final eq = line.indexOf('=');
      if (eq < 0) throw FormatException('Invalid line: "$line"');
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();

      if (section == 'interface') {
        iface[key] = value;
      } else if (section == 'peer') {
        peers.last[key] = value;
      } else {
        throw FormatException('Key "$key" outside of a section');
      }
    }

    if (iface.isEmpty) throw const FormatException('Missing [Interface] section');
    if (peers.isEmpty) throw const FormatException('Missing [Peer] section');
    if (peers.length > 1) {
      throw const FormatException('Only one [Peer] is supported by this client');
    }
    final peer = peers.first;

    String need(Map<String, String> m, String k, String where) =>
        m[k] ?? (throw FormatException('Missing "$k" in $where'));

    List<String> list(String? v) => (v == null || v.isEmpty)
        ? <String>[]
        : v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final cfg = WgConfig(
      privateKey: need(iface, 'privatekey', '[Interface]'),
      addresses: list(need(iface, 'address', '[Interface]')),
      dns: list(iface['dns']),
      mtu: int.tryParse(iface['mtu'] ?? ''),
      peerPublicKey: need(peer, 'publickey', '[Peer]'),
      presharedKey: peer['presharedkey'],
      allowedIps: list(peer['allowedips'] ?? '0.0.0.0/0, ::/0'),
      endpoint: need(peer, 'endpoint', '[Peer]'),
      keepalive: int.tryParse(peer['persistentkeepalive'] ?? ''),
    );
    cfg.validate();
    return cfg;
  }

  /// Builds a config from the JSON your backend returns + the on-device private key.
  factory WgConfig.fromProvision(Map<String, dynamic> j, String privateKey) {
    List<String> strs(dynamic v) => v is List
        ? v.map((e) => e.toString()).toList()
        : (v == null ? <String>[] : v.toString().split(',').map((e) => e.trim()).toList());
    final cfg = WgConfig(
      privateKey: privateKey,
      addresses: strs(j['address']),
      dns: strs(j['dns']),
      mtu: (j['mtu'] as num?)?.toInt(),
      peerPublicKey: j['server_public_key'] as String,
      presharedKey: j['preshared_key'] as String?,
      allowedIps: j['allowed_ips'] == null ? ['0.0.0.0/0', '::/0'] : strs(j['allowed_ips']),
      endpoint: j['endpoint'] as String,
      keepalive: (j['keepalive'] as num?)?.toInt() ?? 25,
    );
    cfg.validate();
    return cfg;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------
  void validate() {
    _checkKey(privateKey, 'PrivateKey');
    _checkKey(peerPublicKey, 'PublicKey');
    if (presharedKey != null && presharedKey!.isNotEmpty) {
      _checkKey(presharedKey!, 'PresharedKey');
    }
    if (addresses.isEmpty) throw const FormatException('Interface Address is empty');
    if (!RegExp(r'^[^\s:]+:\d{1,5}$|^\[.+\]:\d{1,5}$').hasMatch(endpoint)) {
      throw FormatException('Endpoint must be host:port, got "$endpoint"');
    }
  }

  static void _checkKey(String key, String name) {
    try {
      if (base64.decode(key).length != 32) throw const FormatException('len');
    } catch (_) {
      throw FormatException('$name is not a valid 32-byte base64 key');
    }
  }

  // ---------------------------------------------------------------------------
  // Serialize back to wg-quick text (what the plugin wants).
  // ---------------------------------------------------------------------------
  String toWgQuick() {
    final b = StringBuffer()
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $privateKey')
      ..writeln('Address = ${addresses.join(', ')}');
    if (dns.isNotEmpty) b.writeln('DNS = ${dns.join(', ')}');
    if (mtu != null) b.writeln('MTU = $mtu');
    b
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = $peerPublicKey');
    if (presharedKey != null && presharedKey!.isNotEmpty) {
      b.writeln('PresharedKey = $presharedKey');
    }
    b
      ..writeln('AllowedIPs = ${allowedIps.join(', ')}')
      ..writeln('Endpoint = $endpoint');
    if (keepalive != null) b.writeln('PersistentKeepalive = $keepalive');
    return b.toString();
  }
}

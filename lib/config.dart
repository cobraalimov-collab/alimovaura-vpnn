/// App-wide configuration. Edit these before building.

/// Base URL of YOUR backend (see README → "Backend API contract").
const String kApiBaseUrl = 'https://api.your-domain.com/v1';

/// While `true` the app does NOT call your backend:
///  * any email + any 6-digit code "logs in"
///  * a demo server list is shown
///  * the WireGuard config used to connect is [kDevWgConf] below
/// Set to `false` once your API is live.
const bool kUseMockBackend = true;

/// Paste a real client config (.conf) from your own WireGuard server here to test
/// the tunnel end-to-end in mock mode. NEVER ship a real config in a release build.
const String kDevWgConf = '''
# [Interface]
# PrivateKey = <client-private-key-base64>
# Address = 10.8.0.2/32
# DNS = 1.1.1.1
#
# [Peer]
# PublicKey = <server-public-key-base64>
# AllowedIPs = 0.0.0.0/0, ::/0
# Endpoint = vpn.example.com:51820
# PersistentKeepalive = 25
''';

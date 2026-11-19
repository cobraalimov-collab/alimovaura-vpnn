/// Connection lifecycle as the UI understands it (independent of the plugin's enum).
enum ConnStatus { disconnected, connecting, connected, disconnecting }

class VpnServer {
  const VpnServer({
    required this.id,
    required this.country,
    required this.city,
    required this.flag,
    this.pingMs,
  });

  final String id;
  final String country;
  final String city;
  final String flag; // emoji flag
  final int? pingMs; // optional, supplied by the API

  factory VpnServer.fromJson(Map<String, dynamic> j) => VpnServer(
        id: j['id'].toString(),
        country: j['country'] as String,
        city: (j['city'] as String?) ?? '',
        flag: (j['flag'] as String?) ?? '🌐',
        pingMs: (j['ping_ms'] as num?)?.toInt(),
      );
}

class VpnState {
  const VpnState({
    this.status = ConnStatus.disconnected,
    this.server,
    this.startedAt,
    this.downBytesPerSec = 0,
    this.upBytesPerSec = 0,
    this.error,
  });

  final ConnStatus status;
  final VpnServer? server;
  final DateTime? startedAt;
  final double downBytesPerSec;
  final double upBytesPerSec;
  final String? error;

  VpnState copyWith({
    ConnStatus? status,
    VpnServer? server,
    DateTime? startedAt,
    bool clearStart = false,
    double? downBytesPerSec,
    double? upBytesPerSec,
    String? error,
    bool clearError = false,
  }) =>
      VpnState(
        status: status ?? this.status,
        server: server ?? this.server,
        startedAt: clearStart ? null : (startedAt ?? this.startedAt),
        downBytesPerSec: downBytesPerSec ?? this.downBytesPerSec,
        upBytesPerSec: upBytesPerSec ?? this.upBytesPerSec,
        error: clearError ? null : (error ?? this.error),
      );
}

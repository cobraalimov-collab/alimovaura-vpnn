import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import 'models.dart';
import 'vpn_engine.dart';

// ------------------------------------------------------------ singletons ----
final storageProvider = Provider((_) => const FlutterSecureStorage());
final apiProvider = Provider((ref) => ApiService(ref.watch(storageProvider)));
final engineProvider = Provider((ref) {
  final e = VpnEngine();
  ref.onDispose(e.dispose);
  return e;
});
final trafficProvider = Provider((_) => TrafficSource());

// ---------------------------------------------------------------- servers ----
final serversProvider =
    FutureProvider<List<VpnServer>>((ref) => ref.watch(apiProvider).fetchServers());
final selectedServerProvider = StateProvider<VpnServer?>((_) => null);

// ------------------------------------------------------------------- auth ----
class AuthState {
  const AuthState({this.email, this.signedIn = false, this.codeSent = false, this.busy = false, this.error});
  final String? email;
  final bool signedIn;
  final bool codeSent;
  final bool busy;
  final String? error;

  AuthState copyWith({String? email, bool? signedIn, bool? codeSent, bool? busy, String? error, bool clearError = false}) =>
      AuthState(
        email: email ?? this.email,
        signedIn: signedIn ?? this.signedIn,
        codeSent: codeSent ?? this.codeSent,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState();
  }

  ApiService get _api => ref.read(apiProvider);

  Future<void> _restore() async {
    final email = await _api.savedEmail();
    if (email != null) state = AuthState(email: email, signedIn: true);
  }

  Future<void> requestCode(String email) async {
    state = state.copyWith(busy: true, email: email, clearError: true);
    try {
      await _api.requestEmailCode(email);
      state = state.copyWith(busy: false, codeSent: true);
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    }
  }

  Future<bool> verify(String code) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.verifyEmailCode(state.email!, code);
      state = state.copyWith(busy: false, signedIn: true, codeSent: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    }
  }

  void backToEmail() => state = state.copyWith(codeSent: false, clearError: true);

  Future<void> signOut() async {
    await ref.read(vpnProvider.notifier).disconnect();
    await _api.signOut();
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

// -------------------------------------------------------------------- VPN ----
class VpnController extends Notifier<VpnState> {
  StreamSubscription<ConnStatus>? _sub;
  Timer? _poll;
  Timer? _connectTimeout;
  DateTime? _connectingSince;
  int? _lastRx, _lastTx;

  @override
  VpnState build() {
    final engine = ref.read(engineProvider);
    engine.ensureInitialized().catchError((_) {}); // errors surface on connect()
    _sub = engine.statusStream.listen(_onStatus);
    ref.onDispose(() {
      _sub?.cancel();
      _poll?.cancel();
      _connectTimeout?.cancel();
    });
    return const VpnState();
  }

  Future<void> connect(VpnServer server) async {
    if (state.status != ConnStatus.disconnected) return;
    _connectingSince = DateTime.now();
    state = state.copyWith(status: ConnStatus.connecting, server: server, clearError: true);

    // Safety net: never sit on "Connecting" forever.
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 30), () {
      if (state.status == ConnStatus.connecting) {
        disconnect();
        state = state.copyWith(error: 'Connection timed out. Try another server.');
      }
    });

    try {
      final cfg = await ref.read(apiProvider).provisionPeer(server); // (1) get WG config
      await ref.read(engineProvider).connect(cfg); // (2) start tunnel
      // (3) the plugin now emits connecting -> connected via statusStream.
    } on ApiException catch (e) {
      _fail(e.message);
    } on VpnEngineException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Unexpected error: $e');
    }
  }

  Future<void> disconnect() async {
    if (state.status == ConnStatus.disconnected) return;
    _connectTimeout?.cancel();
    state = state.copyWith(status: ConnStatus.disconnecting);
    try {
      await ref.read(engineProvider).disconnect();
    } on VpnEngineException catch (e) {
      state = state.copyWith(error: e.message);
    }
    _apply(ConnStatus.disconnected);
  }

  void _fail(String msg) {
    _connectTimeout?.cancel();
    _apply(ConnStatus.disconnected);
    state = state.copyWith(error: msg);
  }

  void clearError() => state = state.copyWith(clearError: true);

  // Plugin -> UI.
  void _onStatus(ConnStatus s) {
    // The plugin can emit an initial "disconnected" right after we asked to connect.
    if (s == ConnStatus.disconnected &&
        state.status == ConnStatus.connecting &&
        _connectingSince != null &&
        DateTime.now().difference(_connectingSince!) < const Duration(seconds: 3)) {
      return;
    }
    _apply(s);
  }

  void _apply(ConnStatus s) {
    if (s == state.status) return;
    switch (s) {
      case ConnStatus.connected:
        _connectTimeout?.cancel();
        state = state.copyWith(status: s, startedAt: DateTime.now());
        _startPolling();
      case ConnStatus.disconnected:
        _connectTimeout?.cancel();
        _stopPolling();
        state = state.copyWith(status: s, clearStart: true, downBytesPerSec: 0, upBytesPerSec: 0);
      default:
        state = state.copyWith(status: s);
    }
  }

  // Live speed = delta of byte counters per second.
  void _startPolling() {
    _stopPolling();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      final r = await ref.read(trafficProvider).read();
      if (r == null) return;
      if (_lastRx != null && _lastTx != null) {
        state = state.copyWith(
          downBytesPerSec: math.max(0, r.$1 - _lastRx!).toDouble(),
          upBytesPerSec: math.max(0, r.$2 - _lastTx!).toDouble(),
        );
      }
      _lastRx = r.$1;
      _lastTx = r.$2;
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    _lastRx = _lastTx = null;
  }
}

final vpnProvider = NotifierProvider<VpnController, VpnState>(VpnController.new);

/// Ticks once per second while connected -> drives the connection timer.
final elapsedProvider = StreamProvider.autoDispose<Duration>((ref) async* {
  final started = ref.watch(vpnProvider.select((s) => s.startedAt));
  if (started == null) {
    yield Duration.zero;
    return;
  }
  while (true) {
    yield DateTime.now().difference(started);
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

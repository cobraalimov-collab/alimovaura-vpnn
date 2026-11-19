import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';
import 'models.dart';
import 'wg_config.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything that talks to YOUR backend lives here.
///
/// Flow:
///  1. requestEmailCode(email)         POST /auth/email/request
///  2. verifyEmailCode(email, code)    POST /auth/email/verify   -> { "token": "..." }
///  3. fetchServers()                  GET  /servers             -> [ {id,country,city,flag,ping_ms} ]
///  4. provisionPeer(server)           POST /wireguard/peer      -> { address, dns, server_public_key,
///                                                                   endpoint, allowed_ips, preshared_key? }
///
/// Security design: the WireGuard PRIVATE key is generated on the phone and never
/// sent anywhere. Only the PUBLIC key is uploaded so the server can add it as a peer.
class ApiService {
  ApiService(this._storage)
      : _dio = Dio(BaseOptions(
          baseUrl: kApiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
        )) {
    // Attach "Authorization: Bearer <token>" to every request.
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      final t = await _storage.read(key: _kToken);
      if (t != null) o.headers['Authorization'] = 'Bearer $t';
      h.next(o);
    }));
  }

  static const _kToken = 'auth_token';
  static const _kEmail = 'auth_email';
  static const _kPriv = 'wg_private';
  static const _kPub = 'wg_public';

  final FlutterSecureStorage _storage;
  final Dio _dio;

  // ---------------------------------------------------------------- session --
  Future<String?> savedEmail() async =>
      (await _storage.read(key: _kToken)) == null ? null : _storage.read(key: _kEmail);

  Future<void> signOut() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kEmail);
  }

  // ------------------------------------------------------------------- auth --
  Future<void> requestEmailCode(String email) async {
    if (kUseMockBackend) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return;
    }
    await _guard(() => _dio.post('/auth/email/request', data: {'email': email}));
  }

  /// Verifies the emailed code, stores the token securely, returns nothing.
  Future<void> verifyEmailCode(String email, String code) async {
    if (kUseMockBackend) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _storage.write(key: _kToken, value: 'mock-token');
      await _storage.write(key: _kEmail, value: email);
      return;
    }
    final res = await _guard(
        () => _dio.post('/auth/email/verify', data: {'email': email, 'code': code}));
    final token = (res.data as Map)['token'] as String?;
    if (token == null) throw ApiException('Server did not return a token');
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kEmail, value: email);
  }

  // ---------------------------------------------------------------- servers --
  Future<List<VpnServer>> fetchServers() async {
    if (kUseMockBackend) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return const [
        VpnServer(id: 'de-fra', country: 'Germany', city: 'Frankfurt', flag: '🇩🇪', pingMs: 24),
        VpnServer(id: 'nl-ams', country: 'Netherlands', city: 'Amsterdam', flag: '🇳🇱', pingMs: 31),
        VpnServer(id: 'us-nyc', country: 'USA', city: 'New York', flag: '🇺🇸', pingMs: 98),
        VpnServer(id: 'sg-sin', country: 'Singapore', city: 'Singapore', flag: '🇸🇬', pingMs: 176),
      ];
    }
    final res = await _guard(() => _dio.get('/servers'));
    final list = (res.data as List).cast<Map<String, dynamic>>();
    return list.map(VpnServer.fromJson).toList();
  }

  // ------------------------------------------------------------- WG peering --
  /// Registers this device's public key on [server] and returns a ready-to-use config.
  Future<WgConfig> provisionPeer(VpnServer server) async {
    if (kUseMockBackend) {
      if (kDevWgConf.split('\n').every((l) => l.trim().isEmpty || l.trim().startsWith('#'))) {
        throw ApiException(
            'Mock mode: paste a real WireGuard .conf into kDevWgConf (lib/config.dart).');
      }
      try {
        return WgConfig.parse(kDevWgConf);
      } on FormatException catch (e) {
        throw ApiException('kDevWgConf is invalid: ${e.message}');
      }
    }

    final keys = await _deviceKeys();
    final res = await _guard(() => _dio.post('/wireguard/peer', data: {
          'server_id': server.id,
          'public_key': keys.pub,
        }));
    try {
      return WgConfig.fromProvision(Map<String, dynamic>.from(res.data as Map), keys.priv);
    } on FormatException catch (e) {
      throw ApiException('Server returned an invalid WireGuard config: ${e.message}');
    }
  }

  /// Loads the device key pair, generating it once (Curve25519 / X25519).
  Future<({String priv, String pub})> _deviceKeys() async {
    final priv = await _storage.read(key: _kPriv);
    final pub = await _storage.read(key: _kPub);
    if (priv != null && pub != null) return (priv: priv, pub: pub);

    final pair = await X25519().newKeyPair();
    final privBytes = await pair.extractPrivateKeyBytes();
    final pubBytes = (await pair.extractPublicKey()).bytes;
    final p = base64Encode(privBytes);
    final q = base64Encode(pubBytes);
    await _storage.write(key: _kPriv, value: p);
    await _storage.write(key: _kPub, value: q);
    return (priv: p, pub: q);
  }

  // ----------------------------------------------------------------- helper --
  Future<Response<dynamic>> _guard(Future<Response<dynamic>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map && data['message'] is String)
          ? data['message'] as String
          : (e.response?.statusCode == 401
              ? 'Session expired. Please sign in again.'
              : (e.type == DioExceptionType.connectionError ||
                      e.type == DioExceptionType.connectionTimeout
                  ? 'Cannot reach the server. Check your connection.'
                  : 'Request failed (${e.response?.statusCode ?? e.type.name})'));
      throw ApiException(msg);
    }
  }
}

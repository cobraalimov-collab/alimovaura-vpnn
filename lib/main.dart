import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config.dart';
import 'models.dart';
import 'providers.dart';

// ----------------------------------------------------------------- palette ---
const kBg = Color(0xFF060708);
const kCard = Color(0xFF0D0F12);
const kGreen = Color(0xFF2DE89A);
const kCyan = Color(0xFF22E5FF);
const kAmber = Color(0xFFFFB84D);
const kGrey = Color(0xFF4A525C);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBg,
  ));
  runApp(const ProviderScope(child: NodeShieldApp()));
}

class NodeShieldApp extends StatelessWidget {
  const NodeShieldApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NodeShield',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kGreen, secondary: kCyan, surface: kCard),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      );
}

// =============================================================== HOME SCREEN ==
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Android 13+: ask for notification permission once (VPN status notification).
    Future.microtask(() => Permission.notification.request());
  }

  Future<void> _toggle(VpnServer? server) async {
    final vpn = ref.read(vpnProvider);
    final ctrl = ref.read(vpnProvider.notifier);

    if (vpn.status == ConnStatus.connected || vpn.status == ConnStatus.connecting) {
      await ctrl.disconnect();
      return;
    }
    if (server == null) {
      _snack('No server available yet.');
      return;
    }
    if (!kUseMockBackend && !ref.read(authProvider).signedIn) {
      await showAuthSheet(context);
      if (!ref.read(authProvider).signedIn) return;
    }
    await ctrl.connect(server);
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnProvider);
    final auth = ref.watch(authProvider);
    final servers = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider) ?? servers.valueOrNull?.firstOrNull;

    // Show errors from the controller as snackbars.
    ref.listen<String?>(vpnProvider.select((s) => s.error), (_, e) {
      if (e != null) {
        _snack(e);
        ref.read(vpnProvider.notifier).clearError();
      }
    });

    final connected = vpn.status == ConnStatus.connected;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.25),
            radius: 1.0,
            colors: [(connected ? kGreen : kGrey).withAlpha(connected ? 85 : 40), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _Header(planLabel: auth.signedIn ? 'Premium' : 'Guest', onAccount: () => showAuthSheet(context)),
                const SizedBox(height: 8),
                const _TimerBlock(),
                Expanded(
                  child: Center(
                    child: PowerButton(status: vpn.status, onTap: () => _toggle(selected)),
                  ),
                ),
                Text(_subtitle(vpn),
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
                const SizedBox(height: 14),
                _ServerPill(server: selected, loading: servers.isLoading, onTap: () => showServerSheet(context)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _StatCard(
                          label: 'DOWNLOAD',
                          value: _mbps(vpn.downBytesPerSec),
                          icon: Icons.arrow_downward_rounded,
                          color: kGreen)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                          label: 'UPLOAD',
                          value: _mbps(vpn.upBytesPerSec),
                          icon: Icons.arrow_upward_rounded,
                          color: kCyan)),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _mbps(double bytesPerSec) => (bytesPerSec * 8 / 1e6).toStringAsFixed(2);

  static String _subtitle(VpnState s) {
    switch (s.status) {
      case ConnStatus.disconnected:
        return 'Tap to connect';
      case ConnStatus.connecting:
        return 'Negotiating keys…';
      case ConnStatus.connected:
        return 'via ${s.server?.city ?? ''}, ${s.server?.country ?? ''}';
      case ConnStatus.disconnecting:
        return 'Closing tunnel…';
    }
  }
}

// ================================================================== WIDGETS ===
class _Header extends StatelessWidget {
  const _Header({required this.planLabel, required this.onAccount});
  final String planLabel;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          const SizedBox(width: 44),
          Expanded(
            child: Column(children: [
              const Text('NODESHIELD',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w300, letterSpacing: 7)),
              const SizedBox(height: 2),
              Text(planLabel, style: const TextStyle(fontSize: 14, color: Colors.white70)),
            ]),
          ),
          IconButton(onPressed: onAccount, icon: const Icon(Icons.account_circle_outlined, size: 28)),
        ]),
      );
}

class _TimerBlock extends ConsumerWidget {
  const _TimerBlock();

  static String _fmt(Duration d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vpnProvider.select((s) => s.status));
    final elapsed = ref.watch(elapsedProvider).valueOrNull ?? Duration.zero;
    final color = switch (status) {
      ConnStatus.connected => kGreen,
      ConnStatus.connecting => kAmber,
      _ => kGrey,
    };
    final label = switch (status) {
      ConnStatus.connected => 'Connected',
      ConnStatus.connecting => 'Connecting…',
      ConnStatus.disconnecting => 'Disconnecting…',
      ConnStatus.disconnected => 'Disconnected',
    };
    return Column(children: [
      const Text('Connection time', style: TextStyle(color: Colors.white70, fontSize: 13)),
      Text(_fmt(elapsed),
          style: const TextStyle(
              fontSize: 44, fontWeight: FontWeight.w300, letterSpacing: 2, fontFeatures: [FontFeature.tabularFigures()])),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_user_outlined, color: color, size: 20),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 15)),
      ]),
    ]);
  }
}

class PowerButton extends StatelessWidget {
  const PowerButton({super.key, required this.status, required this.onTap});
  final ConnStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (ring, icon, glow) = switch (status) {
      ConnStatus.connected => (kGreen, kCyan, 1.0),
      ConnStatus.connecting || ConnStatus.disconnecting => (kAmber.withAlpha(40), kAmber, .6),
      ConnStatus.disconnected => (kGrey, const Color(0xFF828CA0), 0.0),
    };
    final busy = status == ConnStatus.connecting || status == ConnStatus.disconnecting;

    return Semantics(
      button: true,
      label: status == ConnStatus.disconnected ? 'Connect' : 'Disconnect',
      child: GestureDetector(
        onTap: status == ConnStatus.disconnecting ? null : onTap,
        child: SizedBox(
          width: 230,
          height: 230,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              width: 222,
              height: 222,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF050607),
                border: Border.all(color: ring, width: 17),
                boxShadow: [
                  BoxShadow(color: kGreen.withAlpha((120 * glow).round()), blurRadius: 60, spreadRadius: 4),
                  BoxShadow(color: ring.withAlpha((70 * glow).round()), blurRadius: 120),
                ],
              ),
              child: Icon(Icons.power_settings_new_rounded, size: 76, color: icon),
            ),
            if (busy)
              const SizedBox(
                width: 222,
                height: 222,
                child: CircularProgressIndicator(strokeWidth: 8, color: kAmber),
              ),
          ]),
        ),
      ),
    );
  }
}

class _ServerPill extends StatelessWidget {
  const _ServerPill({required this.server, required this.loading, required this.onTap});
  final VpnServer? server;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.white12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Text(server?.flag ?? '🌐', style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  loading ? 'Loading servers…' : (server == null ? 'Choose location' : '${server!.country} · ${server!.city}'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (server?.pingMs != null) _PingBadge(ms: server!.pingMs!),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white60),
            ]),
          ),
        ),
      );
}

class _PingBadge extends StatelessWidget {
  const _PingBadge({required this.ms});
  final int ms;
  @override
  Widget build(BuildContext context) {
    final c = ms < 60 ? kGreen : (ms < 130 ? kAmber : const Color(0xFFFF4FA3));
    return Text('$ms ms', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'));
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54)),
            Icon(icon, size: 16, color: color),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            const SizedBox(width: 4),
            const Text('Mbps', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ]),
      );
}

// ============================================================ SERVER SHEET ====
Future<void> showServerSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0C10),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _ServerSheet(),
    );

class _ServerSheet extends ConsumerWidget {
  const _ServerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final selected = ref.watch(selectedServerProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Choose location', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            IconButton(onPressed: () => ref.invalidate(serversProvider), icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 8),
          servers.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Could not load servers.\n$e')),
            data: (list) => Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final s = list[i];
                  final active = (selected ?? list.first).id == s.id;
                  return ListTile(
                    tileColor: kCard,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: active ? kCyan.withAlpha(140) : Colors.white12)),
                    leading: Text(s.flag, style: const TextStyle(fontSize: 28)),
                    title: Text(s.country, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(s.city, style: const TextStyle(color: Colors.white54)),
                    trailing: s.pingMs == null ? null : _PingBadge(ms: s.pingMs!),
                    onTap: () async {
                      Navigator.of(context).pop();
                      ref.read(selectedServerProvider.notifier).state = s;
                      // Switching while connected: reconnect through the new server.
                      final ctrl = ref.read(vpnProvider.notifier);
                      if (ref.read(vpnProvider).status != ConnStatus.disconnected) {
                        await ctrl.disconnect();
                        await ctrl.connect(s);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ============================================================== AUTH SHEET ====
Future<void> showAuthSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0C10),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _AuthSheet(),
    );

class _AuthSheet extends ConsumerStatefulWidget {
  const _AuthSheet();
  @override
  ConsumerState<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<_AuthSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final ctrl = ref.read(authProvider.notifier);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (auth.signedIn) ...[
            Text(auth.email ?? 'Signed in', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Premium plan', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () async {
                await ctrl.signOut();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Sign out'),
            ),
          ] else ...[
            Text(auth.codeSent ? 'Enter your code' : 'Sign in with email',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(auth.codeSent ? 'We sent a 6-digit code to ${auth.email}' : 'No password needed — one email is all it takes.',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            if (!auth.codeSent)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _dec('you@example.com', Icons.mail_outline),
              )
            else
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _dec('123456', Icons.lock_outline),
              ),
            if (auth.error != null) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(auth.error!, style: const TextStyle(color: Color(0xFFFF4FA3), fontSize: 12)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: kGreen, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: auth.busy
                    ? null
                    : () async {
                        if (!auth.codeSent) {
                          final e = _email.text.trim();
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e)) return;
                          await ctrl.requestCode(e);
                        } else if (_code.text.length == 6) {
                          final ok = await ctrl.verify(_code.text);
                          if (ok && context.mounted) Navigator.pop(context);
                        }
                      },
                child: auth.busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(auth.codeSent ? 'Verify & continue' : 'Send code'),
              ),
            ),
            if (auth.codeSent)
              TextButton(onPressed: ctrl.backToEmail, child: const Text('Use a different email')),
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            // Web3 wallet login is a placeholder; wire up WalletConnect / reown_appkit later.
            OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Wallet login: coming soon'))),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Connect wallet (placeholder)'),
            ),
          ],
        ]),
      ),
    );
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        counterText: '',
        filled: true,
        fillColor: Colors.white.withAlpha(12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}

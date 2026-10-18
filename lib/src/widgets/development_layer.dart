import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../client/notifiable_client.dart';
import '../domain/models.dart';
import '../domain/subscriber.dart';
import '../platform/flutter_platform.dart';
import 'scope.dart';

class DevelopmentLayer extends StatefulWidget {
  const DevelopmentLayer({super.key});

  @override
  State<DevelopmentLayer> createState() => _DevelopmentLayerState();
}

enum _Edge { top, right, bottom, left }

class _DevelopmentLayerState extends State<DevelopmentLayer> {
  NotifiableClient? _client;
  String? _applicationId;
  var _simulator = false;
  var _recap = false;
  var _edge = _Edge.right;
  Offset? _drag;
  var _listening = false;
  MobilePlatform _platform = Platform.isIOS ? MobilePlatform.ios : MobilePlatform.android;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = NotifiableScope.of(context);

    if (!identical(client, _client)) {
      _client?.removeListener(_onClient);
      _client = client;
      client.addListener(_onClient);
      unawaited(_loadDevice(client));
    }

    _syncShortcut();
  }

  Future<void> _loadDevice(NotifiableClient client) async {
    final id = await client.device.applicationId();
    final simulator = await client.device.isSimulator;
    final profile = await client.device.profile();

    if (!mounted || !identical(_client, client)) {
      return;
    }

    setState(() {
      _applicationId = id;
      _simulator = simulator;
      _platform = profile.platform;
    });
  }

  void _onClient() {
    if (mounted) {
      setState(_syncShortcut);
    }
  }

  void _syncShortcut() {
    final development =
        _client?.snapshot.clientConfig?.environment == ClientEnvironment.development;
    final enable = development && _platform == MobilePlatform.ios;

    if (enable && !_listening) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _listening = true;
    } else if (!enable && _listening) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      _listening = false;
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyN ||
        !HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }

    final client = _client;

    if (client == null) {
      return false;
    }

    unawaited(client.setDevIndicator(enabled: true));
    return true;
  }

  @override
  void dispose() {
    if (_listening) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }

    _client?.removeListener(_onClient);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final config = client?.snapshot.clientConfig;

    if (client == null || config?.environment != ClientEnvironment.development) {
      return const SizedBox.shrink();
    }

    final choice = client.snapshot.devIndicator;

    return Stack(
      children: [
        if (choice == null)
          _Sheet(
            child: _Intro(
              config: config!,
              simulator: _simulator,
              onChoose: (enabled) {
                unawaited(client.setDevIndicator(enabled: enabled));
              },
            ),
          ),
        if (choice == DevIndicatorChoice.enabled)
          LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final origin = _drag ?? _origin(size, _edge);
              return Stack(
                children: [
                  Positioned(
                    left: origin.dx,
                    top: origin.dy,
                    child: GestureDetector(
                      onTap: () => setState(() => _recap = true),
                      onPanUpdate: (details) {
                        setState(() {
                          final current = _drag ?? _origin(size, _edge);
                          _drag = current + details.delta;
                        });
                      },
                      onPanEnd: (_) {
                        setState(() {
                          final current = _drag ?? _origin(size, _edge);
                          _edge = _nearest(size, current);
                          _drag = null;
                        });
                      },
                      child: const _Mark(),
                    ),
                  ),
                ],
              );
            },
          ),
        if (_recap)
          _Sheet(
            onDismiss: () => setState(() => _recap = false),
            child: _Recap(
              config: config!,
              platform: _platform,
              applicationId: _applicationId,
              simulator: _simulator,
              diagnosticsEnabled: client.snapshot.diagnostics != DiagnosticsChoice.disabled,
              onDiagnostics: (enabled) {
                unawaited(client.setDiagnostics(enabled: enabled));
              },
              onCopy: client.device.copy,
              onOpen: () {
                final device = client.device;

                if (device is FlutterDevicePort) {
                  unawaited(device.openUrl('https://notifiable.sh/sdk-diagnostics'));
                }
              },
              onHide: () {
                setState(() => _recap = false);
                unawaited(client.setDevIndicator(enabled: false));
              },
            ),
          ),
      ],
    );
  }
}

const _mark = 56.0;

Offset _origin(Size size, _Edge edge) {
  switch (edge) {
    case _Edge.top:
      return Offset((size.width - _mark) / 2, 76);
    case _Edge.bottom:
      return Offset((size.width - _mark) / 2, size.height - _mark - 56);
    case _Edge.left:
      return Offset(20, (size.height - _mark) / 2);
    case _Edge.right:
      return Offset(size.width - _mark - 20, (size.height - _mark) / 2);
  }
}

_Edge _nearest(Size size, Offset origin) {
  final center = Offset(origin.dx + _mark / 2, origin.dy + _mark / 2);
  final distances = <_Edge, double>{
    _Edge.top: center.dy,
    _Edge.bottom: size.height - center.dy,
    _Edge.left: center.dx,
    _Edge.right: size.width - center.dx,
  };
  return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Notifiable',
      button: true,
      child: ClipOval(
        child: Container(
          width: _mark,
          height: _mark,
          color: const Color(0xD9000000),
          child: Image.network(
            'https://notifiable.sh/favicon.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const Icon(Icons.notifications, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child, this.onDismiss});

  final Widget child;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: const Color(0x73000000),
        child: GestureDetector(
          onTap: onDismiss,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.config,
    required this.simulator,
    required this.onChoose,
  });

  final DeliveryConfig config;
  final bool simulator;
  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) {
    final name = config.app?.name ?? 'This app';
    final shortcut = simulator
        ? 'Drag it to the top, right, bottom, or left. It stays on that edge, clear of the screen. Tap it to compare this app with the dashboard. If you hide it, press Command N to show it again.'
        : 'Drag it to the top, right, bottom, or left. It stays on that edge, clear of the screen. Tap it to compare this app with the dashboard.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        _Heading(config: config),
        const SizedBox(height: 14),
        Text(
          'Notifiable registers this device and delivers notifications to people who accept them. $name is in development, so a mark can stay on screen while you test.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xC7FFFFFF), height: 1.35),
        ),
        const SizedBox(height: 10),
        Text(
          shortcut,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0x9EFFFFFF), fontSize: 14, height: 1.35),
        ),
        const SizedBox(height: 16),
        _Button(label: 'Show the mark', filled: true, onPressed: () => onChoose(true)),
        const SizedBox(height: 8),
        _Button(label: 'Not now', filled: false, onPressed: () => onChoose(false)),
      ],
    );
  }
}

class _Recap extends StatelessWidget {
  const _Recap({
    required this.config,
    required this.platform,
    required this.applicationId,
    required this.simulator,
    required this.diagnosticsEnabled,
    required this.onDiagnostics,
    required this.onCopy,
    required this.onOpen,
    required this.onHide,
  });

  final DeliveryConfig config;
  final MobilePlatform platform;
  final String? applicationId;
  final bool simulator;
  final bool diagnosticsEnabled;
  final ValueChanged<bool> onDiagnostics;
  final void Function(String value) onCopy;
  final VoidCallback onOpen;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        _Heading(config: config),
        const SizedBox(height: 14),
        _Identifier(
          platform: platform,
          config: config,
          applicationId: applicationId,
          onCopy: onCopy,
        ),
        const SizedBox(height: 10),
        _Diagnostics(
          enabled: diagnosticsEnabled,
          onChanged: onDiagnostics,
          onOpen: onOpen,
        ),
        if (simulator) ...[
          const SizedBox(height: 10),
          const Text(
            'Press Command N to show the mark again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0x8CFFFFFF), fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        _Button(label: 'Hide the mark', filled: false, onPressed: onHide),
      ],
    );
  }
}

class _Identifier extends StatelessWidget {
  const _Identifier({
    required this.platform,
    required this.config,
    required this.applicationId,
    required this.onCopy,
  });

  final MobilePlatform platform;
  final DeliveryConfig config;
  final String? applicationId;
  final void Function(String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final record = platform == MobilePlatform.ios ? config.ios : config.android;
    final key = platform == MobilePlatform.ios ? 'bundle_id' : 'package_name';
    final raw = record?[key];
    final configured = raw is String && raw.isNotEmpty ? raw : null;
    final check = packageCheck(configured: configured, applicationId: applicationId);
    final label = platform == MobilePlatform.ios ? 'iOS bundle ID' : 'Android package';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0x73FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (check == PackageCheck.match)
                const Icon(Icons.check_circle, color: Color(0xFF59D173), size: 18)
              else if (check == PackageCheck.mismatch)
                const Icon(Icons.error, color: Color(0xFFF25952), size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            configured ?? 'Not set in the dashboard',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          if (check == PackageCheck.mismatch && applicationId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Paste $applicationId into the dashboard.',
              style: const TextStyle(color: Color(0x9EFFFFFF), fontSize: 12),
            ),
            TextButton(
              onPressed: () => onCopy(applicationId!),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Copy $applicationId'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({
    required this.enabled,
    required this.onChanged,
    required this.onOpen,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share SDK diagnostics',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Help improve Notifiable by sharing SDK crash reports during development.',
                      style: TextStyle(color: Color(0x8CFFFFFF), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onChanged),
            ],
          ),
          const Divider(color: Color(0x24FFFFFF)),
          TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Learn what is collected'),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.config});

  final DeliveryConfig config;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AppIcon(url: config.app?.icon, name: config.app?.name),
        const SizedBox(height: 10),
        Text(
          config.app?.name ?? 'Notifiable',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (config.app?.description != null) ...[
          const SizedBox(height: 4),
          Text(
            config.app!.description!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0x9EFFFFFF)),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5BA42),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'DEVELOPMENT',
            style: TextStyle(
              color: Color(0xFF1A1408),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.url, required this.name});

  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final letter = name != null && name!.trim().isNotEmpty ? name!.trim()[0].toUpperCase() : 'N';
    final fallback = ColoredBox(
      color: const Color(0xFFEBEBEB),
      child: Center(
        child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 64,
        height: 64,
        child: url == null
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => fallback,
              ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0x38FFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.filled, required this.onPressed});

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onPressed,
              child: Text(label),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x33FFFFFF)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onPressed,
              child: Text(label),
            ),
    );
  }
}

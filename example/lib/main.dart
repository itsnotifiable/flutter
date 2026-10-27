import 'package:flutter/material.dart';
import 'package:notifiable_flutter/notifiable.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyName = 'notifiable.example.publicKey';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  String? _publicKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_keyName);

    if (!mounted) {
      return;
    }

    setState(() => _publicKey = stored);
  }

  Future<void> _connect(String publicKey) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_keyName, publicKey);

    if (!mounted) {
      return;
    }

    setState(() => _publicKey = publicKey);
  }

  Future<void> _disconnect() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_keyName);

    if (!mounted) {
      return;
    }

    setState(() => _publicKey = null);
  }

  void _open(String url) {
    final path = _routePath(url);
    final page = ExamplePage.matching(path);

    if (page == null) {
      return;
    }

    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => ExampleScreen(page: page)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final publicKey = _publicKey;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: publicKey == null
          ? ConnectScreen(onConnect: _connect)
          : Notifiable(
              publicKey: publicKey,
              deepLinks: ExamplePage.values
                  .map((page) => DeepLink(path: page.path, label: page.title))
                  .toList(),
              onDeepLink: _open,
              child: Home(onDisconnect: _disconnect),
            ),
    );
  }
}

enum ExamplePage {
  orders('/orders', 'Orders'),
  inbox('/inbox', 'Inbox');

  const ExamplePage(this.path, this.title);

  final String path;
  final String title;

  static ExamplePage? matching(String path) {
    for (final page in values) {
      if (page.path == path || page.path == '/$path') {
        return page;
      }
    }

    return null;
  }
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.onConnect});

  final Future<void> Function(String publicKey) onConnect;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Notifiable', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Paste a public key from the dashboard. A development key shows the mark and preview toasts.'),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Public key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final key = _controller.text.trim();

                if (key.isEmpty) {
                  return;
                }

                widget.onConnect(key);
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key, required this.onDisconnect});

  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final notifiable = Notifiable.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: notifiable,
          builder: (context, _) {
            final current = notifiable.snapshot;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  current.ready ? 'Connected' : 'Connecting…',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(_status(current)),
                if (current.error != null) ...[
                  const SizedBox(height: 8),
                  Text(current.error!.message, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    try {
                      await notifiable.requestPermission();
                    } catch (_) {}
                  },
                  child: const Text('Enable notifications'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await notifiable.identify(
                        email: 'ada@example.com',
                        externalId: 'user_123',
                      );
                    } catch (_) {}
                  },
                  child: const Text('Identify Ada'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await notifiable.track(
                        'order.shipped',
                        properties: const {
                          'order': EventProperty.string('1001'),
                          'express': EventProperty.bool(true),
                        },
                      );
                    } catch (_) {}
                  },
                  child: const Text('Track order.shipped'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExampleScreen(page: ExamplePage.orders),
                    ),
                  ),
                  child: const Text('Orders'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExampleScreen(page: ExamplePage.inbox),
                    ),
                  ),
                  child: const Text('Inbox'),
                ),
                TextButton(onPressed: onDisconnect, child: const Text('Disconnect')),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key, required this.page});

  final ExamplePage page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(page.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('This screen is ${page.path}. A notification whose path is ${page.path} opens it.'),
      ),
    );
  }
}

String _status(NotifiableSnapshot snapshot) {
  final subscriber = snapshot.subscriber?.id ?? 'none';
  return 'Permission ${snapshot.permission.value}. Subscriber $subscriber.';
}

String _routePath(String url) {
  final parsed = Uri.tryParse(url);

  if (parsed == null) {
    return url;
  }

  if (parsed.path.isNotEmpty) {
    return parsed.path;
  }

  return url;
}

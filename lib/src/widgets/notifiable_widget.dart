import 'dart:async';

import 'package:flutter/material.dart';

import '../client/notifiable_client.dart';
import '../domain/errors.dart';
import '../domain/models.dart';
import '../domain/ports.dart';
import '../platform/flutter_platform.dart';
import 'dev_toasts.dart';
import 'development_layer.dart';
import 'scope.dart';

class Notifiable extends StatefulWidget {
  const Notifiable({
    super.key,
    this.publicKey,
    this.client,
    this.deepLinks,
    this.onDeepLink,
    this.logger,
    this.storage,
    required this.child,
  }) : assert(
         client != null || publicKey != null,
         'Pass a publicKey or a client.',
       );

  final String? publicKey;
  final NotifiableClient? client;
  final List<DeepLink>? deepLinks;
  final void Function(String url)? onDeepLink;
  final Logger? logger;
  final KeyValueStore? storage;
  final Widget child;

  static NotifiableClient of(BuildContext context) => NotifiableScope.of(context);

  @override
  State<Notifiable> createState() => _NotifiableState();
}

class _NotifiableState extends State<Notifiable> {
  NotifiableClient? _client;
  NotifiableError? _error;
  var _ownsClient = false;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  @override
  void didUpdateWidget(Notifiable oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.client != null) {
      if (!identical(widget.client, _client)) {
        _releaseOwned();
        _mount();
      }
      return;
    }

    if (oldWidget.publicKey != widget.publicKey || oldWidget.client != widget.client) {
      _releaseOwned();
      _mount();
    }
  }

  void _mount() {
    final provided = widget.client;

    if (provided != null) {
      _client = provided;
      _ownsClient = false;
      _error = null;
      unawaited(_start(provided));
      return;
    }

    try {
      final created = NotifiableClient(
        publicKey: widget.publicKey ?? '',
        logger: widget.logger,
        storage: widget.storage,
        push: FlutterPushPort(),
        device: FlutterDevicePort(),
        deepLinks: widget.deepLinks,
        onDeepLink: widget.onDeepLink,
      );
      _client = created;
      _ownsClient = true;
      _error = null;
      unawaited(_start(created));
    } on NotifiableError catch (error) {
      _client = null;
      _ownsClient = false;
      _error = error;
    }
  }

  Future<void> _start(NotifiableClient client) async {
    try {
      await client.start();
    } catch (_) {}
  }

  void _releaseOwned() {
    if (_ownsClient) {
      _client?.dispose();
    }

    _client = null;
    _ownsClient = false;
  }

  @override
  void dispose() {
    _releaseOwned();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final error = _error;

    if (client == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error.message,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return NotifiableScope(
      client: client,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          const DevelopmentLayer(),
          const DevToasts(),
        ],
      ),
    );
  }
}

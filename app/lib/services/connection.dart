import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../widgets/common.dart';

/// L'app si usa online: se all'apertura (o tornando nell'app) manca internet
/// compare un avviso. Appena la connessione torna l'avviso si chiude da solo e
/// le foto si ricaricano.
class Connection {
  Connection({required this.navigator});

  /// Solo nell'app vera: nei test resta spento, salvo chi lo prova.
  static bool enabled = false;

  /// Vero se internet risponde (i test lo sostituiscono).
  static Future<bool> Function() check = _reach;

  static Future<bool> _reach() async {
    try {
      await http
          .head(Uri.parse(AppConfig.siteUrl))
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _pollEvery = Duration(seconds: 5);

  final GlobalKey<NavigatorState> navigator;
  Timer? _start;
  Timer? _poll;
  AppLifecycleListener? _life;
  BuildContext? _dialog;
  bool _offline = false;
  bool _checking = false;

  void start() {
    if (!enabled) return;
    _life = AppLifecycleListener(onResume: _checkOpening);
    // Dopo il logo d'apertura, altrimenti l'avviso resterebbe sotto.
    _start = Timer(
      Duration(milliseconds: introRemainingMs() + 300),
      _checkOpening,
    );
  }

  void dispose() {
    _start?.cancel();
    _poll?.cancel();
    _life?.dispose();
  }

  Future<void> _checkOpening() async {
    if (_offline || _checking) return;
    _checking = true;
    final online = await check();
    _checking = false;
    if (online || _offline) return;
    _offline = true;
    _poll = Timer.periodic(_pollEvery, (_) => _recheck());
    final ctx = navigator.currentContext;
    if (ctx == null || !ctx.mounted) return;
    unawaited(
      showDialog<void>(
        context: ctx,
        builder: (dialog) {
          _dialog = dialog;
          return _OfflineDialog(onRetry: _recheck);
        },
      ).whenComplete(() => _dialog = null),
    );
  }

  /// Vero se internet è tornato.
  Future<bool> _recheck() async {
    if (!_offline) return true;
    if (!await check()) return false;
    if (!_offline) return true;
    _offline = false;
    _poll?.cancel();
    final d = _dialog;
    if (d != null && d.mounted) Navigator.of(d).pop();
    PhotoAspects.instance.retryAll();
    PhotoImage.reloadAll();
    return true;
  }
}

class _OfflineDialog extends StatefulWidget {
  const _OfflineDialog({required this.onRetry});
  final Future<bool> Function() onRetry;

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog> {
  bool _busy = false;
  bool _stillOffline = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    final online = await widget.onRetry();
    if (!mounted || online) return;
    setState(() {
      _busy = false;
      _stillOffline = true;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Siete offline'),
    content: Text(
      _stillOffline
          ? 'Ancora nessuna connessione. Controllate il Wi-Fi o i dati mobili.'
          : 'Per vedere foto e video serve internet. Controllate il Wi-Fi o i '
                'dati mobili.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Continua'),
      ),
      FilledButton(
        onPressed: _busy ? null : _retry,
        child: const Text('Riprova'),
      ),
    ],
  );
}

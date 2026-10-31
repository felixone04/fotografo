import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../theme/app_theme.dart';
import 'line_icons.dart';
import 'site_scaffold.dart' show NavTint;

// ------------------------------------------------------------------ immagini

/// Le ultime foto caricate decodificate (non tutte: occuperebbero troppa memoria).
final _dataCache = <String, Uint8List>{};

/// Decodifica una foto caricata; null se il dato è danneggiato.
Uint8List? _decode(String url) {
  final hit = _dataCache[url];
  if (hit != null) return hit;
  try {
    if (_dataCache.length >= 24) _dataCache.remove(_dataCache.keys.first);
    return _dataCache[url] = base64Decode(url.substring(url.indexOf(',') + 1));
  } on FormatException {
    return null;
  }
}

/// Le foto di Unsplash si possono chiedere alla larghezza esatta che serve.
String _withWidth(String url, int w) {
  if (!url.contains('images.unsplash.com')) return url;
  return url.contains(RegExp(r'[?&]w=\d+'))
      ? url.replaceFirstMapped(RegExp(r'([?&])w=\d+'), (m) => '${m[1]}w=$w')
      : '$url${url.contains('?') ? '&' : '?'}w=$w';
}

/// Proporzioni (larghezza / altezza) delle foto, lette una volta sola e
/// ricordate: servono per il carosello (solo foto orizzontali) e per
/// comporre il collage dei lavori senza tagliare le immagini.
class PhotoAspects extends ChangeNotifier {
  PhotoAspects._();
  static final instance = PhotoAspects._();

  final _known = <String, double>{};
  final _pending = <String>{};
  final _failed = <String>{};

  /// Proporzione nota, oppure null se non ancora letta (o illeggibile).
  double? of(String url) => _known[url];

  /// Vero quando la foto è stata letta, o non si è potuta leggere: non c'è
  /// più niente da aspettare.
  bool settled(String url) =>
      _known.containsKey(url) || _failed.contains(url) || url.trim().isEmpty;

  void _fail(String url) {
    _failed.add(url);
    // Mai durante il disegno di chi ha chiesto la foto.
    Future.microtask(notifyListeners);
  }

  /// Vero solo quando si sa con certezza che la foto non è orizzontale.
  bool notLandscape(String url) => (_known[url] ?? 1.5) <= 1.0;

  /// Si riprova a leggere le foto non riuscite (es. rete tornata).
  void retry(Iterable<String> urls) {
    for (final u in urls) {
      if (_failed.remove(u)) _pending.remove(u);
    }
  }

  /// Tornata la connessione: si riprovano tutte le foto non riuscite.
  void retryAll() {
    _pending.removeAll(_failed);
    _failed.clear();
    notifyListeners();
  }

  void resolveAll(Iterable<String> urls) {
    for (final u in urls) {
      resolve(u);
    }
  }

  void resolve(String url) {
    if (url.trim().isEmpty ||
        _known.containsKey(url) ||
        _failed.contains(url) ||
        !_pending.add(url)) {
      return;
    }
    final ImageProvider provider;
    if (url.startsWith('data:')) {
      final bytes = _decode(url);
      if (bytes == null) {
        _fail(url);
        return;
      }
      provider = MemoryImage(bytes);
    } else {
      // Basta una versione piccola per conoscere le proporzioni.
      provider = NetworkImage(
        _withWidth(url, 480),
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      );
    }
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    void done() => stream.removeListener(l);
    l = ImageStreamListener(
      (info, _) {
        done();
        try {
          final w = info.image.width, h = info.image.height;
          if (w > 0 && h > 0) {
            _known[url] = w / h;
            notifyListeners();
          } else {
            _fail(url);
          }
        } catch (_) {
          // Immagine mostrata dal browser senza accesso ai pixel: proporzioni
          // sconosciute, la si tratta come orizzontale.
          _fail(url);
        }
      },
      onError: (_, _) {
        done();
        _fail(url);
      },
    );
    stream.addListener(l);
  }
}

/// Mostra un'immagine da URL web oppure da un caricamento locale (data URL).
class PhotoImage extends StatelessWidget {
  const PhotoImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;

  Widget _placeholder() => const ColoredBox(
    color: Palette.linen,
    child: Center(child: LineIcon(Ico.camera, color: Palette.ash, size: 28)),
  );

  /// Larghezze a "gradini": evitano di riscaricare la foto a ogni piccolo
  /// ridimensionamento della finestra.
  static const _steps = [480, 800, 1200, 1600, 2000, 2600];

  /// Fa riprovare le foto rimaste senza connessione.
  static void reloadAll() => _reload.value++;
  static final _reload = ValueNotifier<int>(0);

  Widget _network(String src) => ValueListenableBuilder<int>(
    valueListenable: _reload,
    builder: (_, tick, _) => _image(src, tick),
  );

  Widget _image(String src, int tick) => Image.network(
    src,
    key: ValueKey(tick),
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
    frameBuilder: (context, child, frame, sync) {
      if (sync) return child;
      // Durante il caricamento: solo il colore di fondo, poi dissolvenza.
      // Con BoxFit.contain il fondo resta trasparente (si vede la pagina).
      return ColoredBox(
        color: fit == BoxFit.contain ? Colors.transparent : Palette.linen,
        child: AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          child: child,
        ),
      );
    },
    errorBuilder: (_, _, _) => _placeholder(),
  );

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) return _placeholder();
    if (url.startsWith('data:')) {
      final bytes = _decode(url);
      if (bytes == null) return _placeholder();
      return Image.memory(
        bytes,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    // Le foto di Unsplash si chiedono alla larghezza che serve: molto più
    // leggere per miniature e telefoni.
    if (!url.contains('images.unsplash.com')) return _network(url);
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.maxWidth.isFinite) return _network(url);
        final px = box.maxWidth * MediaQuery.devicePixelRatioOf(context);
        final w = _steps.firstWhere((s) => s >= px, orElse: () => _steps.last);
        return _network(_withWidth(url, w));
      },
    );
  }
}

// -------------------------------------------------------------------- reveal

/// Fa comparire il contenuto (dissolvenza + scorrimento) quando entra nella
/// finestra visibile.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 40,
  });
  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  final _key = UniqueKey();
  bool _triggered = false;
  bool _shown = false;

  void _onVisible(VisibilityInfo info) {
    if (_triggered || info.visibleFraction < 0.05) return;
    _triggered = true;
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _key,
      onVisibilityChanged: _onVisible,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _shown ? 1 : 0),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutQuart,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

// ----------------------------------------------------------------- layout

/// Sezione a tutta larghezza con margini laterali fluidi.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.child,
    this.color,
    this.top,
    this.bottom,
  });
  final Widget child;
  final Color? color;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    final v = context.spaceSection;
    final box = Container(
      color: color,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        context.gutter,
        top ?? v,
        context.gutter,
        bottom ?? v,
      ),
      child: child,
    );
    // Una sezione colorata dà il suo colore alla barra in alto.
    return color == null ? box : NavTint(color: color!, child: box);
  }
}

/// Piccola etichetta tipo cartellino (es. "— AREA CLIENTI").
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.number, this.color = Palette.ink});
  final String text;
  final String? number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentInk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (number != null) ...[
          Text('($number)', style: label(11, color: accent)),
          const SizedBox(width: 12),
        ],
        Container(width: 28, height: 1, color: color.withValues(alpha: 0.5)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(text.toUpperCase(), style: label(11, color: color)),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- bottoni

/// Bottone a pillola con freccia che ruota al passaggio del mouse.
class PillButton extends StatefulWidget {
  const PillButton(
    this.text, {
    super.key,
    required this.onTap,
    this.filled = true,
    this.big = false,
    this.loading = false,
    this.icon = Ico.arrowOutward,
    this.expand = false,
  });
  final String text;
  final VoidCallback? onTap;
  final bool filled;
  final bool big;
  final bool loading;
  final Ico icon;

  /// Occupa tutta la larghezza: testo a sinistra, cerchio in fondo a destra.
  final bool expand;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const base = Palette.ink;
    final Color bg;
    final Color fg;
    if (widget.filled) {
      bg = _hover ? context.accent : base;
      fg = _hover ? Palette.ink : Palette.paper;
    } else {
      bg = _hover ? base : Colors.transparent;
      fg = _hover ? Palette.paper : base;
    }
    final enabled = widget.onTap != null && !widget.loading;
    final h = widget.big ? 64.0 : 50.0;
    return Semantics(
      button: true,
      label: widget.text,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            height: h,
            padding: EdgeInsets.only(left: h * 0.5, right: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(h),
              border: Border.all(color: widget.filled ? bg : base, width: 1.2),
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Flexible(
                  fit: widget.expand ? FlexFit.tight : FlexFit.loose,
                  child: Text(
                    widget.text.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label(widget.big ? 13 : 11.5, color: fg),
                  ),
                ),
                SizedBox(width: h * 0.3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: h - 12,
                  height: h - 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fg.withValues(alpha: _hover ? 0.14 : 0.1),
                  ),
                  child: widget.loading
                      ? Padding(
                          padding: EdgeInsets.all(h * 0.28),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        )
                      : AnimatedRotation(
                          turns: _hover ? 0.125 : 0,
                          duration: const Duration(milliseconds: 260),
                          child: Center(
                            child: LineIcon(
                              widget.icon,
                              size: h * 0.42,
                              color: fg,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Link testuale con sottolineatura animata.
class HoverLink extends StatefulWidget {
  const HoverLink(
    this.text, {
    super.key,
    required this.onTap,
    required this.style,
    this.active = false,
  });
  final String text;
  final VoidCallback onTap;
  final TextStyle style;
  final bool active;

  @override
  State<HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<HoverLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = _hover || widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.text, style: widget.style),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                height: 1.2,
                width: on ? 24 : 0,
                color: widget.style.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Istante di avvio dell'app (impostato in `main`).
DateTime appStartedAt = DateTime.now();

/// Durata del logo d'apertura (2 s + dissolvenza): sul web è in
/// `web/index.html`, nell'app è [AppIntro].
const splashMs = 2300;

/// Vero nell'app Android, dove il logo d'apertura lo disegna Flutter
/// ([AppIntro], acceso da `main`): il carosello aspetta che sparisca.
bool introInApp = false;

/// Millisecondi che mancano alla fine del logo d'apertura dell'app.
int introRemainingMs() {
  if (!introInApp) return 0;
  final passed = DateTime.now().difference(appStartedAt).inMilliseconds;
  return math.max(0, splashMs - passed);
}

/// Logo d'apertura dell'app, come quello del sito: fondo bianco, logo nero e
/// una linea che si riempie; dopo 2 secondi sfuma.
class AppIntro extends StatefulWidget {
  const AppIntro({super.key, required this.child});
  final Widget child;

  @override
  State<AppIntro> createState() => _AppIntroState();
}

class _AppIntroState extends State<AppIntro> {
  bool _visible = true;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        widget.child,
        if (!_gone)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 800),
                onEnd: () => setState(() => _gone = true),
                child: ColoredBox(
                  color: Palette.paper,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeOutCubic,
                          builder: (_, t, child) => Opacity(
                            opacity: t,
                            child: Transform.scale(
                              scale: 0.96 + 0.04 * t,
                              child: child,
                            ),
                          ),
                          child: Image.asset(
                            'assets/brand/logo.png',
                            width: math.min(380, w * 0.7),
                            semanticLabel: 'Studio 54',
                          ),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          width: math.min(160, w * 0.4),
                          height: 1,
                          color: Palette.line,
                          alignment: Alignment.centerLeft,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(seconds: 2),
                            curve: Curves.easeInOut,
                            builder: (_, v, _) => FractionallySizedBox(
                              widthFactor: v,
                              child: Container(color: Palette.ink),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

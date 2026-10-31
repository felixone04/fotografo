import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'pages/admin/admin_page.dart';
import 'pages/bio_page.dart';
import 'pages/client_area_page.dart';
import 'pages/home_page.dart';
import 'pages/quote_page.dart';
import 'pages/works_page.dart';
import 'services/back_handlers.dart';
import 'services/connection.dart';
import 'services/system_bars.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

/// Permette il trascinamento con il mouse nei carousel (di default solo touch).
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  /// Nessuna barra di scorrimento visibile: si scorre lo stesso.
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Sul telefono il sito sta tra la barra di stato (ora, batteria) e quella
/// dei gesti, su fondo bianco: le pagine misurano solo lo spazio libero.
class _SystemBars extends StatelessWidget {
  const _SystemBars({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Il sistema legge questo stile a metà della barra di stato: deve coprire
    // anche quella, non solo la pagina. Scuri ora e batteria, sempre.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Palette.paper,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: SystemBars.fullScreen,
        builder: (context, full, inner) {
          // A tutto schermo (carosello, foto) la foto riempie anche notch e
          // lineetta dell'iPhone, che le pagine ricevono come margine interno.
          // Altrove (telefono girato: anche di lato) la pagina sta fra le barre.
          final outer = full ? EdgeInsets.zero : mq.padding;
          // Sempre la stessa struttura: se cambiasse, Flutter ricostruirebbe
          // l'app da capo e ripartirebbe il logo d'apertura.
          return ColoredBox(
            color: Palette.paper,
            child: Padding(
              padding: outer,
              child: MediaQuery(
                data: mq.copyWith(
                  size: Size(
                    mq.size.width - outer.horizontal,
                    mq.size.height - outer.vertical,
                  ),
                  padding: full ? mq.padding : EdgeInsets.zero,
                  viewPadding: full ? mq.viewPadding : EdgeInsets.zero,
                ),
                child: inner!,
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }
}

/// iPhone e iPad non hanno il tasto indietro: strisciando dal bordo sinistro si
/// torna indietro come farebbe il tasto su Android (stesso percorso).
class _EdgeSwipeBack extends StatefulWidget {
  const _EdgeSwipeBack({required this.onBack, required this.child});
  final VoidCallback onBack;
  final Widget child;

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return widget.child;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 18,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _dx = 0,
            onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
            onHorizontalDragEnd: (d) {
              if (_dx > 60 || (d.primaryVelocity ?? 0) > 500) widget.onBack();
            },
          ),
        ),
      ],
    );
  }
}

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) =>
    CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (_, a, _, c) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: c,
      ),
    );

/// Il tasto indietro (telefono, tablet) ripercorre le pagine viste fino alla
/// home e lì si ferma: l'app non si chiude mai da sola. Finestre, menu e foto
/// a schermo intero si chiudono come sempre.
class _BackToHome extends RootBackButtonDispatcher {
  _BackToHome(this.router) {
    router.routerDelegate.addListener(_track);
    _track();
    BackHandlers.back = _goBack;
  }

  final GoRouter router;
  final List<String> _history = [];

  String get _here => router.routerDelegate.currentConfiguration.uri.toString();

  void _track() {
    final here = _here;
    if (here == '/') {
      _history
        ..clear()
        ..add(here);
      return;
    }
    // Una pagina già vista: si riparte da lì, senza giri a vuoto.
    final i = _history.indexOf(here);
    if (i >= 0) {
      _history.removeRange(i + 1, _history.length);
    } else {
      _history.add(here);
    }
  }

  @override
  Future<bool> invokeCallback(Future<bool> defaultValue) async {
    Route<dynamic>? top;
    router.routerDelegate.navigatorKey.currentState?.popUntil((r) {
      top = r;
      return true;
    });
    final t = top;
    if (t != null && (t.settings is! Page || t.willHandlePopInternally)) {
      return super.invokeCallback(defaultValue);
    }
    // Una pagina che gestisce da sé il tasto (es. le cartelle dell'area
    // clienti).
    if (BackHandlers.handle()) return true;
    _goBack();
    return true;
  }

  void _goBack() {
    if (_history.length > 1) {
      _history.removeLast();
      router.go(_history.last);
    } else if (_here != '/') {
      router.go('/');
    }
  }

  void dispose() {
    router.routerDelegate.removeListener(_track);
    if (BackHandlers.back == _goBack) BackHandlers.back = null;
  }
}

class StudioApp extends StatefulWidget {
  const StudioApp({super.key});

  @override
  State<StudioApp> createState() => _StudioAppState();
}

class _StudioAppState extends State<StudioApp> {
  final _content = GlobalKey();
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(path: '/', pageBuilder: (c, s) => _fade(s, const HomePage())),
      GoRoute(
        path: '/preventivo',
        pageBuilder: (c, s) => _fade(s, const QuotePage()),
      ),
      GoRoute(
        path: '/area-clienti',
        pageBuilder: (c, s) => _fade(s, const ClientAreaPage()),
      ),
      GoRoute(
        path: '/lavori',
        pageBuilder: (c, s) => _fade(s, const WorksPage()),
        routes: [
          GoRoute(
            path: ':id',
            pageBuilder: (c, s) => _fade(
              s,
              WorkPage(
                key: ValueKey(s.pathParameters['id']),
                id: s.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/biografia',
        pageBuilder: (c, s) => _fade(s, const BioPage()),
      ),
      GoRoute(
        path: '/admin',
        pageBuilder: (c, s) => NoTransitionPage(
          key: s.pageKey,
          child: const AdminPage(section: null),
        ),
        routes: [
          GoRoute(
            path: ':section',
            pageBuilder: (c, s) => NoTransitionPage(
              key: s.pageKey,
              child: AdminPage(section: s.pathParameters['section']),
            ),
          ),
        ],
      ),
    ],
    errorPageBuilder: (c, s) => _fade(s, const HomePage()),
  );
  late final _back = _BackToHome(_router);
  late final _connection = Connection(
    navigator: _router.routerDelegate.navigatorKey,
  );

  @override
  void initState() {
    super.initState();
    _connection.start();
  }

  @override
  void dispose() {
    _connection.dispose();
    _back.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp.router(
      onGenerateTitle: (_) =>
          '${state.content.studioName} · ${state.content.tagline}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.site(Color(state.content.accent)),
      // Testo di sistema ingrandito: fino al 150%, oltre la grafica non regge.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.5,
        child: ScreenScale(
          child: _SystemBars(
            // Toccando fuori da un campo la tastiera si chiude: su iPhone il
            // tastierino del telefono non ha un tasto per farlo.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: _EdgeSwipeBack(
                onBack: () => _back.invokeCallback(Future.value(false)),
                // La chiave conserva l'app (pagine, scorrimento, logo d'apertura
                // già visto) anche quando cambia la cornice intorno: barre del
                // telefono che compaiono o spariscono, schermo che si gira.
                child: KeyedSubtree(
                  key: _content,
                  child: introInApp ? AppIntro(child: child!) : child!,
                ),
              ),
            ),
          ),
        ),
      ),
      scrollBehavior: _AppScrollBehavior(),
      locale: const Locale('it', 'IT'),
      supportedLocales: const [Locale('it', 'IT')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerDelegate: _router.routerDelegate,
      routeInformationParser: _router.routeInformationParser,
      routeInformationProvider: _router.routeInformationProvider,
      backButtonDispatcher: _back,
    );
  }
}

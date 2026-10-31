// L'app si usa online: senza internet, all'apertura compare un avviso.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_fotografico/services/connection.dart';

import 'support/harness.dart';

void main() {
  setUpAll(setUpTestEnv);

  var online = false;
  var checks = 0;
  final realCheck = Connection.check;

  setUp(() {
    online = false;
    checks = 0;
    Connection.enabled = true;
    Connection.check = () async {
      checks++;
      return online;
    };
  });
  tearDown(() {
    Connection.enabled = false;
    Connection.check = realCheck;
  });

  const phone = Size(390, 844);
  final notice = find.text('Siete offline');

  testWidgets('con internet nessun avviso', (tester) async {
    online = true;
    await pumpApp(tester, await loadState(), size: phone);
    await settle(tester, 800);
    expect(notice, findsNothing);
    await disposeApp(tester);
  });

  testWidgets('senza internet l\'avviso compare e si può continuare', (
    tester,
  ) async {
    await pumpApp(tester, await loadState(), size: phone);
    await settle(tester, 800);
    expect(notice, findsOneWidget);

    await tester.tap(find.text('Continua'));
    await settle(tester, 800);
    expect(notice, findsNothing);
    // Non ricompare a ogni controllo mentre si resta offline.
    await settle(tester, 12000);
    expect(notice, findsNothing);
    await disposeApp(tester);
  });

  testWidgets('Riprova: se manca ancora lo dice, se è tornata si chiude', (
    tester,
  ) async {
    await pumpApp(tester, await loadState(), size: phone);
    await settle(tester, 800);
    await tester.tap(find.text('Riprova'));
    await settle(tester, 400);
    expect(find.textContaining('Ancora nessuna connessione'), findsOneWidget);

    online = true;
    await tester.tap(find.text('Riprova'));
    await settle(tester, 800);
    expect(notice, findsNothing);
    await disposeApp(tester);
  });

  testWidgets('quando internet torna l\'avviso si chiude da solo', (
    tester,
  ) async {
    await pumpApp(tester, await loadState(), size: phone);
    await settle(tester, 800);
    expect(notice, findsOneWidget);
    online = true;
    await settle(tester, 6000);
    expect(notice, findsNothing);
    // Tornata la connessione smette di controllare.
    final dopo = checks;
    await settle(tester, 12000);
    expect(checks, dopo);
    await disposeApp(tester);
  });

  testWidgets('il tasto indietro chiude l\'avviso e resta nell\'app', (
    tester,
  ) async {
    await pumpApp(tester, await loadState(), size: phone);
    await settle(tester, 800);
    await tester.binding.handlePopRoute();
    await settle(tester, 800);
    expect(notice, findsNothing);
    expect(find.byType(Scaffold), findsWidgets);
    await disposeApp(tester);
  });

  testWidgets('l\'avviso sta nello schermo anche sul telefono girato', (
    tester,
  ) async {
    await pumpApp(tester, await loadState(), size: const Size(568, 320));
    await settle(tester, 800);
    expect(notice, findsOneWidget);
    await disposeApp(tester);
  });
}

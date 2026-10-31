// I caratteri stanno dentro l'app: ogni peso usato deve caricarsi senza internet.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const weights = [
  FontWeight.w300,
  FontWeight.w400,
  FontWeight.w500,
  FontWeight.w600,
  FontWeight.w700,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'tutti i pesi di entrambi i caratteri si caricano senza internet',
    () async {
      GoogleFonts.config.allowRuntimeFetching = false;
      for (final w in weights) {
        for (final s in FontStyle.values) {
          GoogleFonts.josefinSans(fontWeight: w, fontStyle: s);
          GoogleFonts.jost(fontWeight: w, fontStyle: s);
        }
      }
      GoogleFonts.jostTextTheme();
      await GoogleFonts.pendingFonts();
    },
  );

  test('il codice usa solo i pesi che sono dentro l\'app', () {
    final used = RegExp(r'FontWeight\.(w\d00|bold|normal)');
    final ok = {'w300', 'w400', 'w500', 'w600', 'w700', 'bold', 'normal'};
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in sources) {
      for (final m in used.allMatches(f.readAsStringSync())) {
        expect(ok, contains(m[1]), reason: f.path);
      }
    }
  });
}

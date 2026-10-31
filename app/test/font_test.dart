// I caratteri stanno dentro l'app: ogni peso usato deve caricarsi senza internet.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart';
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
import 'package:google_fonts/src/google_fonts_variant.dart';

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
      // Se un carattere manca la libreria non dà errore: scrive un messaggio e
      // l'app usa senza dirlo il carattere di sistema.
      final messages = <String>[];
      final original = debugPrint;
      debugPrint = (m, {wrapWidth}) => messages.add('$m');
      addTearDown(() => debugPrint = original);

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final w in weights) {
        for (final s in FontStyle.values) {
          GoogleFonts.josefinSans(fontWeight: w, fontStyle: s);
          GoogleFonts.jost(fontWeight: w, fontStyle: s);
          for (final family in ['JosefinSans', 'Jost']) {
            final variant = GoogleFontsFamilyWithVariant(
              family: family,
              googleFontsVariant: GoogleFontsVariant(
                fontWeight: w,
                fontStyle: s,
              ),
            );
            // Il file vero: flutter test può riusare una copia degli asset.
            final name = variant.toApiFilenamePrefix();
            expect(
              File('assets/fonts/$name.ttf').existsSync(),
              isTrue,
              reason: name,
            );
            expect(
              findFamilyWithVariantAssetPath(variant, manifest.listAssets()),
              isNotNull,
              reason: variant.toApiFilenamePrefix(),
            );
          }
        }
      }
      GoogleFonts.jostTextTheme();
      await GoogleFonts.pendingFonts();
      expect(messages, isEmpty);
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

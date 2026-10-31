import 'package:flutter/foundation.dart'
    show kIsWeb, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'app.dart';
import 'data/repository.dart';
import 'services/connection.dart';
import 'state/app_state.dart';
import 'widgets/common.dart';

Future<void> main() async {
  appStartedAt = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();

  // I caratteri sono in assets/fonts: mai scaricarli da internet. La loro
  // licenza chiede di accompagnarli con il suo testo.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Josefin Sans', 'OFL-JosefinSans.txt'),
      ('Jost', 'OFL-Jost.txt'),
    ]) {
      final text = await rootBundle.loadString('assets/fonts/$file');
      yield LicenseEntryWithLineBreaks([name], text);
    }
  });

  await initializeDateFormatting('it_IT');
  VisibilityDetectorController.instance.updateInterval = const Duration(
    milliseconds: 100,
  );

  final state = AppState(await LocalRepository.open());
  await state.load();

  // Nell'app il logo d'apertura lo disegna Flutter (sul web è in index.html).
  introInApp = !kIsWeb;
  Connection.enabled = !kIsWeb;
  appStartedAt = DateTime.now();
  runApp(ChangeNotifierProvider.value(value: state, child: const StudioApp()));
}

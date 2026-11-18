import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'app_controller.dart';
import 'domain/bible.dart';
import 'ui/common.dart';
import 'ui/notebook.dart';
import 'ui/welcome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final english = await rootBundle.loadString('assets/data/books.json');
    final original = await rootBundle.loadString(
      'assets/data/books-original.json',
    );
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Bijbelmetadata',
      ], await rootBundle.loadString('assets/data/DATA-SOURCES.md'));
      yield LicenseEntryWithLineBreaks([
        'Roboto',
      ], await rootBundle.loadString('assets/fonts/roboto_license.txt'));
    });
    final app = AppController(
      bible: Bible(english, original),
      supportDirectory: await getApplicationSupportDirectory(),
      cacheDirectory: await getApplicationCacheDirectory(),
    );
    runApp(MosterdzaadApp(app));
    await app.start();
  } catch (error) {
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Notice(
                'Mosterdzaad kon niet starten. ${describeError(error)}',
                error: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MosterdzaadApp extends StatelessWidget {
  const MosterdzaadApp(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => MaterialApp(
      title: 'Mosterdzaad',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: const Locale('nl'),
      supportedLocales: const [Locale('nl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: app.repository == null ? WelcomeScreen(app) : NotebookShell(app),
    ),
  );
}

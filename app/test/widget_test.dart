import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mosterdzaad/main.dart';
import 'package:mosterdzaad/app_controller.dart';
import 'package:mosterdzaad/storage/vault_files.dart';
import 'package:mosterdzaad/storage/vault_repository.dart';
import 'helpers.dart';

class TestPicker extends VaultPicker {
  final MemoryFiles memory = MemoryFiles();
  bool cancel = false;
  @override
  Future<VaultLocation?> pick() async => cancel ? null : memory.location;
  @override
  Future<VaultLocation> createChild(VaultLocation parent, String name) async =>
      memory.location;
  @override
  VaultFiles files(VaultLocation location) => memory;
}

class TestController extends AppController {
  TestController(TestPicker picker)
    : super(
        bible: testBible(),
        supportDirectory: Directory.systemTemp.path,
        cacheDirectory: Directory.systemTemp.path,
        picker: picker,
      );
  @override
  Future<void> attach(VaultRepository repo) async {
    repository = repo;
    error = null;
    notifyListeners();
  }

  @override
  Future<void> rebuildIndex() async {
    notifyListeners();
  }
}

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'First start offers both choices, creates a book, and saves a linked note',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = TestController(TestPicker());
      await tester.pumpWidget(MosterdzaadApp(app));
      await tester.pumpAndSettle();
      expect(find.text('Nieuw studieboek maken'), findsOneWidget);
      expect(find.text('Studieboek openen'), findsOneWidget);
      await tester.tap(find.text('Nieuw studieboek maken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Locatie kiezen'));
      await tester.pumpAndSettle();
      expect(app.repository?.name, 'Mijn studieboek');
      await tester.tap(find.text('Nieuwe notitie').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Wat wil je bewaren?'),
        'Mijn eerste gedachte',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Bijbelverwijzingen'),
        'Psalm 23',
      );
      await tester.tap(find.text('Opslaan').first);
      await tester.pumpAndSettle();
      expect(app.ofKind('note').single.text('body'), 'Mijn eerste gedachte');
      expect(app.covered['PSA:23'], {1, 2, 3, 4, 5, 6});
      expect(find.text('Mijn eerste gedachte'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Cancelling the native folder picker keeps onboarding intact', (
    tester,
  ) async {
    final picker = TestPicker()..cancel = true;
    final app = TestController(picker);
    await tester.pumpWidget(MosterdzaadApp(app));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Studieboek openen'));
    await tester.tap(find.text('Studieboek openen'));
    await tester.pumpAndSettle();
    expect(app.repository, isNull);
    expect(app.error, isNull);
    expect(picker.memory.contents, isEmpty);
  });
  testWidgets(
    'Invalid note retains its text and explains the missing connection',
    (tester) async {
      final picker = TestPicker();
      final app = TestController(picker);
      await app.attach(
        await VaultRepository.create(
          picker.memory,
          app.bible,
          'Test',
          'english',
          false,
        ),
      );
      await tester.pumpWidget(MosterdzaadApp(app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nieuwe notitie').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Wat wil je bewaren?'),
        'Dit moet bewaard blijven',
      );
      await tester.tap(find.text('Opslaan').first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Koppel je notitie aan een passage, thema, leesplan of studie.',
        ),
        findsOneWidget,
      );
      expect(find.text('Dit moet bewaard blijven'), findsOneWidget);
      expect(app.ofKind('note'), isEmpty);
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets('Navigate, search and create a plan at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picker = TestPicker();
      final app = TestController(picker);
      await app.attach(
        await VaultRepository.create(
          picker.memory,
          app.bible,
          'Mijn studieboek',
          'english',
          false,
        ),
      );
      await app.save(
        'note',
        noteData(
          app.bible,
          body: 'Rust vinden in Psalm 23',
          references: 'Psalm 23',
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: MosterdzaadApp(app)),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, key, 'overview-${width.toInt()}');
      Future<void> navigate(String label) async {
        if (width < 980) {
          await tester.tap(find.byIcon(Icons.menu));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
      }

      await navigate('Bijbeltracker');
      await screenshot(tester, key, 'tracker-${width.toInt()}');
      await tester.tap(find.text('Genesis'));
      await tester.pumpAndSettle();
      expect(find.text('Notitie bij Genesis 1'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await navigate('Notities');
      await tester.enterText(find.byType(TextField), 'rust');
      await tester.pumpAndSettle();
      expect(find.text('Rust vinden in Psalm 23'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'onvindbaar');
      await tester.pumpAndSettle();
      expect(find.text('Geen notities gevonden'), findsOneWidget);
      await navigate('Leesplannen');
      await tester.tap(find.text('Nieuw toevoegen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Titel'),
        'Een week in de Psalmen',
      );
      await tester.tap(find.text('Sessie 1'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Bijbelverwijzingen'),
        'Psalm 23',
      );
      await tester.tap(find.text('Opslaan').first);
      await tester.pumpAndSettle();
      expect(app.ofKind('plan').single.sessions.first['passages'], isNotEmpty);
      await tester.tap(find.text('Een week in de Psalmen'));
      await tester.pumpAndSettle();
      await screenshot(tester, key, 'plan-${width.toInt()}');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await navigate('Instellingen');
      await screenshot(tester, key, 'settings-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
    testWidgets('Welcome layout and screenshot at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MosterdzaadApp(TestController(TestPicker())),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/welcome-${width.toInt()}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final font = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf'));
  await font.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}

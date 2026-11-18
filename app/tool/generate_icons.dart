// Explicit asset generation: flutter test tool/generate_icons.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> seedIcon(int size) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..scale(size / 128);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 128, 128),
    Paint()..color = const Color(0xFFF0F2E8),
  );
  final paint = Paint()..color = const Color(0xFF526C49);
  canvas.drawPath(
    Path()
      ..moveTo(63, 108)
      ..cubicTo(60, 83, 72, 66, 65, 38),
    Paint()
      ..color = const Color(0xFF526C49)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round,
  );
  canvas.drawPath(
    Path()
      ..moveTo(65, 64)
      ..cubicTo(34, 65, 27, 47, 29, 28)
      ..cubicTo(54, 29, 69, 42, 65, 64),
    paint,
  );
  canvas.drawPath(
    Path()
      ..moveTo(65, 85)
      ..cubicTo(91, 86, 105, 66, 101, 47)
      ..cubicTo(80, 49, 66, 65, 65, 85),
    paint,
  );
  canvas.drawPath(
    Path()
      ..moveTo(64, 41)
      ..cubicTo(83, 37, 91, 20, 86, 11)
      ..cubicTo(71, 16, 62, 26, 64, 41),
    paint..color = const Color(0xFF8B9C76),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = (await image.toByteData(
    format: ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  testWidgets('Generate the shared seed icon for native platforms', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final targets = <String, int>{
        for (final entry in {
          'mdpi': 48,
          'hdpi': 72,
          'xhdpi': 96,
          'xxhdpi': 144,
          'xxxhdpi': 192,
        }.entries)
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png':
              entry.value,
        for (final size in [16, 32, 64, 128, 256, 512, 1024])
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png':
              size,
      };
      for (final f in Directory(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset',
      ).listSync().whereType<File>()) {
        final match = RegExp(
          r'Icon-App-([0-9.]+)x[0-9.]+@([123])x.png$',
        ).firstMatch(f.path);
        if (match != null) {
          targets[f.path] = (double.parse(match[1]!) * int.parse(match[2]!))
              .round();
        }
      }
      for (final target in targets.entries) {
        await File(target.key).writeAsBytes(await seedIcon(target.value));
      }
      final png = await seedIcon(256);
      final header = ByteData(22)
        ..setUint16(2, 1, Endian.little)
        ..setUint16(4, 1, Endian.little)
        ..setUint16(10, 1, Endian.little)
        ..setUint16(12, 32, Endian.little)
        ..setUint32(14, png.length, Endian.little)
        ..setUint32(18, 22, Endian.little);
      await File(
        'windows/runner/resources/app_icon.ico',
      ).writeAsBytes([...header.buffer.asUint8List(), ...png]);
    });
  });
}

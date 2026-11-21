import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'common.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: sage,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(Icons.spa_outlined, color: paper, size: 24),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'mosterdzaad',
            style: editorial.copyWith(fontSize: compact ? 21 : 23),
          ),
          if (!compact)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                'RUIMTE VOOR GROEI',
                style: TextStyle(fontSize: 9, letterSpacing: 2, color: muted),
              ),
            ),
        ],
      ),
    ],
  );
}

/// A small vector illustration; bundled with the app and crisp offline.
class GrowingPlant extends StatelessWidget {
  const GrowingPlant({super.key});
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(painter: _PlantPainter()));
}

class _PlantPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 240);
    canvas.drawCircle(
      const Offset(120, 116),
      91,
      Paint()..color = const Color(0xFFDEE5CF),
    );
    final line = Paint()
      ..color = const Color(0xFFB8C5A4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 64; i++) {
      canvas.drawArc(
        const Rect.fromLTWH(16, 12, 208, 208),
        i * math.pi / 32,
        .025,
        false,
        line,
      );
    }
    final stem = Path()
      ..moveTo(112, 220)
      ..cubicTo(108, 175, 129, 136, 121, 80);
    canvas.drawPath(
      stem,
      Paint()
        ..color = sage
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    void leaf(Offset base, Offset tip, double spread, Color color) {
      final dx = tip.dx - base.dx, dy = tip.dy - base.dy;
      final middle = Offset((base.dx + tip.dx) / 2, (base.dy + tip.dy) / 2);
      final length = math.sqrt(dx * dx + dy * dy);
      final normal = Offset(-dy / length * spread, dx / length * spread);
      final path = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          middle.dx + normal.dx,
          middle.dy + normal.dy,
          tip.dx,
          tip.dy,
        )
        ..quadraticBezierTo(
          middle.dx - normal.dx,
          middle.dy - normal.dy,
          base.dx,
          base.dy,
        );
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawLine(
        base,
        Offset(tip.dx * .92 + base.dx * .08, tip.dy * .92 + base.dy * .08),
        Paint()
          ..color = const Color(0xFFDCE7CC)
          ..strokeWidth = 1.4,
      );
    }

    leaf(
      const Offset(117, 183),
      const Offset(51, 146),
      25,
      const Color(0xFFA2AF86),
    );
    leaf(const Offset(121, 153), const Offset(183, 104), 30, sage);
    leaf(
      const Offset(121, 128),
      const Offset(64, 77),
      28,
      const Color(0xFF839876),
    );
    leaf(
      const Offset(122, 104),
      const Offset(156, 46),
      23,
      const Color(0xFF657F58),
    );
    canvas.drawLine(
      const Offset(82, 221),
      const Offset(150, 221),
      line..strokeWidth = 2,
    );
    for (final point in [const Offset(46, 46), const Offset(191, 185)]) {
      canvas.drawCircle(point, 3, Paint()..color = gold);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlantPainter oldDelegate) => false;
}

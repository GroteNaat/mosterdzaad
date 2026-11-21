import 'package:material_ui/material_ui.dart';

const sage = Color(0xFF4F694B);
const ink = Color(0xFF293E32);
const muted = Color(0xFF697565);
const paper = Color(0xFFF8F7F2);
const sidebarGreen = Color(0xFFEDF0E4);
const softGreen = Color(0xFFE8EEDC);
const gold = Color(0xFFAF8C4D);
const editorial = TextStyle(fontFamily: 'Lora', color: ink, height: 1.25);
ThemeData appTheme() => ThemeData(
  fontFamily: 'Roboto',
  useMaterial3: true,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontFamily: 'Lora',
      fontSize: 38,
      color: ink,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Lora',
      fontSize: 30,
      color: ink,
      height: 1.3,
    ),
    headlineSmall: TextStyle(fontFamily: 'Lora', fontSize: 25, color: ink),
    titleLarge: TextStyle(
      fontFamily: 'Lora',
      fontSize: 22,
      color: ink,
      height: 1.3,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
    bodySmall: TextStyle(fontSize: 12, height: 1.45, color: muted),
  ),
  colorScheme: ColorScheme.fromSeed(seedColor: sage, surface: paper),
  scaffoldBackgroundColor: paper,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF9F8F3),
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: Color(0xFFD4DCCB)),
    ),
    filled: true,
    fillColor: Colors.white,
    alignLabelWithHint: true,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE0E4D8)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
);

class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFEDE5) : const Color(0xFFE9EDE2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? const Color(0xFF77391D) : const Color(0xFF33442C),
        ),
      ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      spacing: 24,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 6),
            Text(subtitle),
          ],
        ),
        ?action,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.text, {super.key, this.action});
  final String title, text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.spa_outlined, size: 36, color: sage),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(text),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Doorgaan',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

String shortDate(DateTime time) {
  final d = time.toLocal();
  return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
}

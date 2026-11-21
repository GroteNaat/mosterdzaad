import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../domain/bible.dart';
import '../domain/entry.dart';
import '../domain/plan_progress.dart';
import 'brand.dart';
import 'common.dart';
import 'editor.dart';
import 'notebook.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage(this.app, {super.key, required this.navigate});
  final AppController app;
  final ValueChanged<int> navigate;

  @override
  Widget build(BuildContext context) {
    final books = app.bible.books(
      app.repository!.scheme,
      extra: app.repository!.extra,
    );
    final covered = app.covered;
    final counts = {
      for (final b in books)
        b.code: List.generate(
          b.chapters.length,
          (i) => covered['${b.code}:${i + 1}']?.length ?? 0,
        ).fold(0, (sum, count) => sum + count),
    };
    final total = books.fold(0, (sum, b) => sum + b.verseCount);
    final done = counts.values.fold(0, (sum, n) => sum + n);
    final chapters = books.fold(
      0,
      (sum, b) =>
          sum +
          List.generate(
            b.chapters.length,
            (i) =>
                (covered['${b.code}:${i + 1}']?.length ?? 0) == b.chapters[i],
          ).where((full) => full).length,
    );
    final notes = app.ofKind('note');
    final activePlans = app
        .ofKind('plan')
        .where((p) => completedSessions(p, notes) < p.sessions.length)
        .toList();
    return PageBody([
      const Text(
        'JOUW PERSOONLIJKE STUDIEPLEK',
        style: TextStyle(fontSize: 10, letterSpacing: 2, color: muted),
      ),
      const SizedBox(height: 10),
      const PageHeading(
        'Ruimte om te groeien.',
        'Lees, verwonder en bewaar wat je raakt.',
      ),
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: softGreen,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE4CF)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KLEIN BEGINNEN, DIEP WORTELEN',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.6,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Een open Bijbel.\nEen aandachtig hart.',
                      style: editorial.copyWith(
                        fontSize: constraints.maxWidth < 500 ? 27 : 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Je hoeft niet alles tegelijk te ontdekken.\nBegin met een passage en schrijf op wat je opvalt.',
                      style: TextStyle(color: muted, height: 1.8),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => navigate(1),
                      label: const Text('Kies een Bijbelboek'),
                      icon: const Icon(Icons.north_east, size: 15),
                      iconAlignment: IconAlignment.end,
                    ),
                  ],
                ),
              ),
              if (constraints.maxWidth >= 560)
                const SizedBox(width: 220, height: 220, child: GrowingPlant()),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 800 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _Stat(
                width,
                '$done',
                'Verzen met een notitie',
                '${(total == 0 ? 0 : 100 * done / total).toStringAsFixed(1).replaceAll('.', ',')}% van je Bijbel',
                suffix: '/ $total',
                onTap: () => navigate(1),
              ),
              _Stat(
                width,
                '$chapters',
                'Volledige hoofdstukken',
                'Vers voor vers ontdekt',
                onTap: () => navigate(1),
              ),
              _Stat(
                width,
                '${notes.length}',
                'Bewaarde notities',
                'Gedachten om naar terug te keren',
                onTap: () => navigate(2),
              ),
              _Stat(
                width,
                '${app.ofKind('study').length}',
                'Bijbelstudies',
                'Alleen of samen aan tafel',
                onTap: () => navigate(4),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                'Jouw weg door de Bijbel',
                action: TextButton.icon(
                  onPressed: () => navigate(1),
                  label: const Text('Open tracker'),
                  icon: const Icon(Icons.north_east, size: 14),
                  iconAlignment: IconAlignment.end,
                ),
              ),
              const Text(
                'Elk boek een stukje van het verhaal.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final content = SizedBox(
                    width: constraints.maxWidth < 600
                        ? 680
                        : constraints.maxWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final b in books)
                          Expanded(child: _BookBar(app, b, counts[b.code]!)),
                      ],
                    ),
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: content,
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    books.first.name,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                  Text(
                    books.last.name,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Een vers telt mee zodra er een notitie aan gekoppeld is.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, constraints) {
          final thoughts = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle(
                'Laatste gedachten',
                action: FilledButton.icon(
                  onPressed: () => editEntry(context, app, 'note'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nieuwe notitie'),
                ),
              ),
              const SizedBox(height: 14),
              if (notes.isEmpty)
                const EmptyState(
                  'Hier begint je verzameling.',
                  'Bewaar wat je raakt. Een zin is al een mooi begin.',
                ),
              for (final n in notes.take(4)) NoteCard(app, n),
              if (notes.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => navigate(2),
                    label: const Text('Alle notities'),
                    icon: const Icon(Icons.north_east, size: 14),
                    iconAlignment: IconAlignment.end,
                  ),
                ),
            ],
          );
          final plans = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle(
                'Jouw leesplannen',
                action: TextButton.icon(
                  onPressed: () => navigate(3),
                  label: const Text('Bekijk alles'),
                  icon: const Icon(Icons.north_east, size: 14),
                  iconAlignment: IconAlignment.end,
                ),
              ),
              const SizedBox(height: 14),
              if (activePlans.isEmpty)
                EmptyState(
                  'Op jouw eigen ritme.',
                  app.ofKind('plan').isEmpty
                      ? 'Maak een leesplan en geef elke dag ruimte aan een nieuwe gedachte.'
                      : 'Je leesplannen zijn afgerond. Er is ruimte voor een nieuw begin.',
                  action: TextButton.icon(
                    onPressed: () => editEntry(context, app, 'plan'),
                    icon: const Icon(Icons.add),
                    label: const Text('Nieuw leesplan'),
                  ),
                ),
              for (final plan in activePlans) _ActivePlan(app, plan),
            ],
          );
          return constraints.maxWidth >= 850
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: thoughts),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: plans),
                  ],
                )
              : Column(children: [thoughts, const SizedBox(height: 28), plans]);
        },
      ),
      const SizedBox(height: 30),
      const Center(
        child: Text(
          'Kleine momenten. Diepe wortels.',
          style: TextStyle(fontFamily: 'Lora', fontSize: 15, color: muted),
        ),
      ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.action});
  final String title;
  final Widget action;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        action,
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(
    this.width,
    this.value,
    this.label,
    this.caption, {
    this.suffix,
    required this.onTap,
  });
  final double width;
  final String value, label, caption;
  final String? suffix;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 40,
                child: Text(
                  label,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(value, style: editorial.copyWith(fontSize: 32)),
                  if (suffix != null)
                    Text(
                      suffix!,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: Text(
                  caption,
                  maxLines: 2,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BookBar extends StatelessWidget {
  const _BookBar(this.app, this.book, this.count);
  final AppController app;
  final Book book;
  final int count;
  @override
  Widget build(BuildContext context) => Tooltip(
    excludeFromSemantics: true,
    message: '${book.name}: $count van ${book.verseCount} verzen',
    child: Semantics(
      label: '${book.name}: $count van ${book.verseCount} verzen',
      button: true,
      child: InkWell(
        onTap: () => openBook(context, app, book, 1),
        child: Container(
          height: 68,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: book.testament == 'NT'
                ? const Color(0xFFE2E8D8)
                : const Color(0xFFEBEEE5),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: count == 0
                ? 0
                : (count / book.verseCount).clamp(.04, 1),
            child: const ColoredBox(color: sage),
          ),
        ),
      ),
    ),
  );
}

class _ActivePlan extends StatelessWidget {
  const _ActivePlan(this.app, this.plan);
  final AppController app;
  final Entry plan;
  @override
  Widget build(BuildContext context) {
    final completed = completedSessions(plan, app.ofKind('note'));
    return Card(
      child: InkWell(
        onTap: () => openDetail(context, app, plan.id),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${plan.sessions.length} SESSIES',
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: muted,
                ),
              ),
              const SizedBox(height: 10),
              Text(plan.title, style: editorial.copyWith(fontSize: 21)),
              if (plan.text('description').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    plan.text('description'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted),
                  ),
                ),
              const SizedBox(height: 18),
              ExcludeSemantics(
                child: LinearProgressIndicator(
                  value: completed / plan.sessions.length,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: softGreen,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$completed van ${plan.sessions.length} sessies met een notitie',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Verder met dit plan',
                    style: TextStyle(color: sage, fontWeight: FontWeight.w600),
                  ),
                  Icon(Icons.arrow_forward, color: sage, size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

from urllib.parse import urlencode
from django.contrib import messages
from django.core import serializers
from django.core.paginator import Paginator
from django.db import connection, transaction
from django.db.models import Count, Q
from django.db.models.deletion import ProtectedError
from django.http import HttpResponse, JsonResponse, Http404
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.views.decorators.http import require_GET, require_http_methods
from .models import Preferences, Note, Plan, PlanSession, Study, Theme, Group, Passage
from .forms import NoteForm, PlanForm, PlanMetaForm, SessionFormSet, StudyForm, ThemeForm, GroupForm, PreferencesForm
from .bible import visible_books, book_by_code, book_progress, coverage


def all_notes():
    return Note.objects.prefetch_related('passages', 'plans', 'themes', 'studies')


@require_GET
def dashboard(request):
    prefs, covered = Preferences.current(), coverage()
    progress = [book_progress(b, covered) for b in visible_books(prefs)]
    total, read = sum(b['total'] for b in progress), sum(b['read'] for b in progress)
    return render(request, 'dashboard.html', {'active': 'home', 'progress': progress, 'read': read, 'total': total, 'percent': round(100 * read / total, 1), 'note_count': Note.objects.count(), 'study_count': Study.objects.count(), 'recent_notes': all_notes()[:3], 'plans': Plan.objects.annotate(session_count=Count('sessions'))[:3], 'complete_chapters': sum(b['complete_chapters'] for b in progress)})


@require_GET
def tracker(request):
    prefs, covered = Preferences.current(), coverage()
    progress = [book_progress(b, covered) for b in visible_books(prefs)]
    return render(request, 'tracker.html', {'active': 'tracker', 'progress': progress})


@require_GET
def book_detail(request, code):
    prefs = Preferences.current()
    book = next((b for b in visible_books(prefs) if b['code'] == code), None)
    if not book:
        raise Http404
    covered = coverage()
    try:
        chapter = int(request.GET.get('chapter', '1'))
    except ValueError:
        raise Http404
    if not 1 <= chapter <= len(book['chapters']):
        raise Http404
    count = book['chapters'][chapter - 1]
    verses = [{'number': v, 'read': v in covered.get((code, chapter), set())} for v in range(1, count + 1)]
    notes = all_notes().filter(passages__book=code, passages__chapter=chapter).distinct()
    return render(request, 'book.html', {'active': 'tracker', 'book': book_progress(book, covered), 'chapter': chapter, 'verses': verses, 'notes': notes, 'new_note_url': reverse('note-new') + '?' + urlencode({'references': f'{book["name"]} {chapter}'})})


@require_GET
def notes(request):
    items = all_notes()
    q = request.GET.get('q', '').strip()
    if q:
        items = items.filter(Q(title__icontains=q) | Q(body__icontains=q) | Q(themes__name__icontains=q) | Q(plans__title__icontains=q) | Q(studies__title__icontains=q)).distinct()
    label, initial = '', {}
    for key, model, relation in [('plan', Plan, 'plans'), ('theme', Theme, 'themes'), ('study', Study, 'studies')]:
        if request.GET.get(key):
            try:
                obj = get_object_or_404(model, pk=int(request.GET[key]))
            except ValueError:
                raise Http404
            items = items.filter(**{relation: obj})
            label, initial[key] = str(obj), obj.pk
    code = request.GET.get('book')
    if code:
        try:
            book = book_by_code(code, Preferences.current().versification)
            chapter = int(request.GET.get('chapter', '1'))
            verse = int(request.GET.get('verse', '0'))
            if not 1 <= chapter <= len(book['chapters']) or not 0 <= verse <= book['chapters'][chapter - 1]:
                raise ValueError
        except (ValueError, StopIteration):
            raise Http404
        condition = Q(passages__book=code, passages__chapter=chapter)
        label = f'{book["name"]} {chapter}'
        if verse:
            condition &= Q(passages__start__lte=verse, passages__end__gte=verse)
            label += f':{verse}'
        items = items.filter(condition).distinct()
        initial['references'] = label
    page = Paginator(items, 15).get_page(request.GET.get('page'))
    params = request.GET.copy()
    params.pop('page', None)
    context = {'active': 'notes', 'page': page, 'q': q, 'bundle_label': label, 'new_note_url': reverse('note-new') + ('?' + urlencode(initial) if initial else ''), 'filter_query': params.urlencode()}
    template = 'partials/note_results.html' if request.headers.get('HX-Request') and request.headers.get('HX-Target') == 'note-results' else 'notes.html'
    response = render(request, template, context)
    response['Vary'] = 'HX-Request, HX-Target'
    return response


@require_http_methods(['GET', 'POST'])
def note_edit(request, pk=None):
    note = get_object_or_404(Note, pk=pk) if pk else None
    initial = {}
    if not note:
        initial['references'] = request.GET.get('references', '')
        for key, model, field in [('plan', Plan, 'plans'), ('theme', Theme, 'themes'), ('study', Study, 'studies')]:
            if request.GET.get(key):
                try:
                    initial[field] = [get_object_or_404(model, pk=int(request.GET[key])).pk]
                except ValueError:
                    raise Http404
    form = NoteForm(request.POST or None, instance=note, initial=initial)
    if request.method == 'POST' and form.is_valid():
        with transaction.atomic():
            note = form.save()
        messages.success(request, 'Notitie opgeslagen. Je tracker is bijgewerkt.')
        return redirect('note-detail', pk=note.pk)
    return render(request, 'note_form.html', {'active': 'notes', 'form': form, 'note': note})


@require_GET
def note_detail(request, pk):
    return render(request, 'note_detail.html', {'active': 'notes', 'note': get_object_or_404(all_notes(), pk=pk)})


@require_GET
def bundles(request):
    passages = Passage.objects.filter(notes__isnull=False).values('book', 'chapter').annotate(count=Count('notes', distinct=True)).order_by('book', 'chapter')
    book_order = {b['code']: i for i, b in enumerate(visible_books(Preferences.current()))}
    passage_bundles = [{**p, 'name': book_by_code(p['book'])['name']} for p in passages]
    passage_bundles.sort(key=lambda p: (book_order.get(p['book'], 999), p['chapter']))
    return render(request, 'bundles.html', {'active': 'bundles', 'passage_bundles': passage_bundles, 'plans': Plan.objects.annotate(note_count=Count('notes', distinct=True)), 'themes': Theme.objects.annotate(note_count=Count('notes', distinct=True)), 'studies': Study.objects.annotate(note_count=Count('notes', distinct=True))})


@require_GET
def plans(request):
    return render(request, 'plans.html', {'active': 'plans', 'plans': Plan.objects.annotate(session_count=Count('sessions', distinct=True), note_count=Count('notes', distinct=True))})


@require_http_methods(['GET', 'POST'])
def plan_new(request):
    form = PlanForm(request.POST or None)
    if request.method == 'POST' and form.is_valid():
        with transaction.atomic():
            plan = form.save()
            PlanSession.objects.bulk_create([PlanSession(plan=plan, number=i) for i in range(1, form.cleaned_data['days'] + 1)])
        return redirect('plan-edit', pk=plan.pk)
    return render(request, 'simple_form.html', {'active': 'plans', 'form': form, 'title': 'Een nieuw leesplan', 'eyebrow': 'STAP 1 VAN 2', 'intro': 'Kies hoeveel dagen of sessies je wilt plannen. Daarna voeg je per sessie passages en een overdenking toe.', 'submit': 'Verder: sessies invullen'})


@require_http_methods(['GET', 'POST'])
def plan_edit(request, pk):
    plan = get_object_or_404(Plan, pk=pk)
    meta = PlanMetaForm(request.POST or None, instance=plan)
    formset = SessionFormSet(request.POST or None, instance=plan)
    if request.method == 'POST':
        meta_valid, sessions_valid = meta.is_valid(), formset.is_valid()
        if meta_valid and sessions_valid:
            with transaction.atomic():
                meta.save()
                formset.save()
            messages.success(request, 'Leesplan opgeslagen.')
            return redirect('plan-detail', pk=pk)
    return render(request, 'plan_form.html', {'active': 'plans', 'plan': plan, 'form': meta, 'formset': formset})


@require_GET
def plan_detail(request, pk):
    plan = get_object_or_404(Plan, pk=pk)
    covered, sessions = coverage(), []
    for session in plan.sessions.prefetch_related('passages'):
        passages = list(session.passages.all())
        complete = bool(passages) and all(set(range(p.start, p.end + 1)) <= covered.get((p.book, p.chapter), set()) for p in passages)
        sessions.append({'session': session, 'passages': passages, 'complete': complete, 'note_url': reverse('note-new') + '?' + urlencode({'plan': pk, 'references': '\n'.join(map(str, passages))})})
    return render(request, 'plan_detail.html', {'active': 'plans', 'plan': plan, 'sessions': sessions, 'complete_count': sum(s['complete'] for s in sessions), 'notes': all_notes().filter(plans=plan)[:6]})


@require_GET
def studies(request):
    items = Study.objects.select_related('group').annotate(note_count=Count('notes'))
    if request.GET.get('group'):
        try:
            items = items.filter(group=get_object_or_404(Group, pk=int(request.GET['group'])))
        except ValueError:
            raise Http404
    return render(request, 'studies.html', {'active': 'studies', 'studies': items, 'groups': Group.objects.all()})


@require_http_methods(['GET', 'POST'])
def study_edit(request, pk=None):
    study = get_object_or_404(Study, pk=pk) if pk else None
    form = StudyForm(request.POST or None, instance=study)
    if request.method == 'POST' and form.is_valid():
        study = form.save()
        messages.success(request, 'Bijbelstudie opgeslagen.')
        return redirect('study-detail', pk=study.pk)
    return render(request, 'simple_form.html', {'active': 'studies', 'form': form, 'title': 'Studie bewerken' if study else 'Een nieuwe bijbelstudie', 'intro': 'Een moment om stil te staan, alleen of met je groep.', 'group_help': True})


@require_GET
def study_detail(request, pk):
    study = get_object_or_404(Study.objects.select_related('group'), pk=pk)
    return render(request, 'study_detail.html', {'active': 'studies', 'study': study, 'notes': all_notes().filter(studies=study)})


@require_http_methods(['GET', 'POST'])
def themes(request):
    form = ThemeForm(request.POST or None)
    if request.method == 'POST' and form.is_valid():
        theme = form.save()
        messages.success(request, 'Thema aangemaakt.')
        return redirect('theme-detail', pk=theme.pk)
    return render(request, 'themes.html', {'active': 'themes', 'themes': Theme.objects.annotate(note_count=Count('notes')), 'form': form})


@require_GET
def theme_detail(request, pk):
    theme = get_object_or_404(Theme, pk=pk)
    return render(request, 'theme_detail.html', {'active': 'themes', 'theme': theme, 'notes': all_notes().filter(themes=theme)})


@require_http_methods(['GET', 'POST'])
def theme_edit(request, pk):
    form = ThemeForm(request.POST or None, instance=get_object_or_404(Theme, pk=pk))
    if request.method == 'POST' and form.is_valid():
        form.save()
        return redirect('theme-detail', pk=pk)
    return render(request, 'simple_form.html', {'active': 'themes', 'title': 'Thema bewerken', 'form': form})


@require_http_methods(['GET', 'POST'])
def groups(request):
    form = GroupForm(request.POST or None)
    if request.method == 'POST' and form.is_valid():
        form.save()
        messages.success(request, 'Groep aangemaakt.')
        return redirect('groups')
    return render(request, 'groups.html', {'active': 'studies', 'form': form, 'groups': Group.objects.annotate(study_count=Count('study'))})


@require_http_methods(['GET', 'POST'])
def group_edit(request, pk):
    form = GroupForm(request.POST or None, instance=get_object_or_404(Group, pk=pk))
    if request.method == 'POST' and form.is_valid():
        form.save()
        return redirect('groups')
    return render(request, 'simple_form.html', {'active': 'studies', 'title': 'Groepsnaam wijzigen', 'form': form})


@require_http_methods(['GET', 'POST'])
def settings(request):
    form = PreferencesForm(request.POST or None, instance=Preferences.current())
    if request.method == 'POST' and form.is_valid():
        form.save()
        messages.success(request, 'Instellingen opgeslagen.')
        return redirect('settings')
    return render(request, 'settings.html', {'active': 'settings', 'form': form})


@require_http_methods(['GET', 'POST'])
def delete(request, kind, pk):
    config = {'note': (Note, 'notes', 'notitie'), 'plan': (Plan, 'plans', 'leesplan'), 'study': (Study, 'studies', 'bijbelstudie'), 'theme': (Theme, 'themes', 'thema'), 'group': (Group, 'groups', 'groep')}
    if kind not in config:
        raise Http404
    model, destination, label = config[kind]
    obj = get_object_or_404(model, pk=pk)
    if request.method == 'POST':
        try:
            obj.delete()
            messages.success(request, f'{label.capitalize()} verwijderd.')
            return redirect(destination)
        except ProtectedError:
            messages.error(request, 'Deze groep wordt nog gebruikt door een studie. Wijzig die studie eerst.')
    return render(request, 'delete.html', {'object': obj, 'kind': kind, 'label': label, 'cancel_url': reverse(destination)})


@require_GET
def export(request):
    with transaction.atomic():
        objects = [obj for model in [Preferences, Group, Theme, Passage, Plan, PlanSession, Study, Note] for obj in model.objects.all()]
        data = serializers.serialize('json', objects, indent=2)
    response = HttpResponse(data, content_type='application/json; charset=utf-8')
    response['Content-Disposition'] = 'attachment; filename="mosterdzaad-export.json"'
    response['Cache-Control'] = 'no-store'
    return response


@require_GET
def health(request):
    with connection.cursor() as cursor:
        cursor.execute('SELECT 1')
    return JsonResponse({'status': 'ok'})

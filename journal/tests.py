import json
from django.core import serializers
from django.core.exceptions import ValidationError
from django.test import TestCase, Client, override_settings
from django.urls import reverse
from .bible import books, visible_books, parse_passages, coverage, book_progress, book_by_code
from .forms import NoteForm, StudyForm, PreferencesForm
from .models import Preferences, Passage, Note, Theme, Plan, PlanSession, Study, Group


class PassageTests(TestCase):
    def setUp(self):
        self.prefs = Preferences.current()

    def test_canon_and_optional_books(self):
        self.assertEqual(len(visible_books(self.prefs)), 66)
        self.assertEqual(sum(len(b['chapters']) for b in visible_books(self.prefs)), 1189)
        self.prefs.deuterocanonical = True
        self.assertEqual(len(visible_books(self.prefs)), 78)
        for scheme in ('english', 'original'):
            for book in books(scheme):
                self.assertTrue(all(isinstance(n, int) and n > 0 for n in book['chapters']))

    def test_multiple_whole_chapters_and_numbered_books(self):
        self.assertEqual(parse_passages('Johannes 3:16–18; 1 Johannes 1:1\nPsalm 23', self.prefs), [('JHN', 3, 16, 18), ('1JN', 1, 1, 1), ('PSA', 23, 1, 6)])
        self.assertEqual(parse_passages('Genesis 1-2', self.prefs), [('GEN', 1, 1, 31), ('GEN', 2, 1, 25)])

    def test_cross_chapter_range_and_duplicate_passages(self):
        self.assertEqual(parse_passages('Genesis 1:30-2:3; Genesis 1:30-31', self.prefs), [('GEN', 1, 30, 31), ('GEN', 2, 1, 3)])

    def test_rejects_invalid_numbers_and_unknown_text(self):
        for text in ['Johannes 0', 'Johannes 22', 'Johannes 3:0', 'Johannes 3:37', 'Johannes 3:18-16', 'Genesis 2-1', 'Genesis 2:3-1:30', 'Geenboek 1:1', 'Johannes 3:16,18', 'Genesis 1-2:3', 'Johannes 3:1; fout']:
            with self.subTest(text=text), self.assertRaises(ValidationError):
                parse_passages(text, self.prefs)

    def test_versification_choice(self):
        with self.assertRaises(ValidationError):
            parse_passages('Joël 4', self.prefs)
        self.prefs.versification = 'original'
        self.assertEqual(parse_passages('Joël 4', self.prefs)[0][1], 4)


class TrackerLayoutTests(TestCase):
    def test_chapter_fill_and_links_with_dutch_number_formatting(self):
        form = NoteForm({'body': 'Een gedachte', 'references': 'Genesis 1:1-8; Genesis 2; Genesis 3:1'})
        self.assertTrue(form.is_valid(), form.errors)
        form.save()
        response = self.client.get(reverse('tracker'))
        chapters = response.context['progress'][0]['chapter_progress']
        self.assertEqual([(c['state'], c['percent']) for c in chapters[:4]], [
            ('partial', 25.8), ('complete', 100.0), ('partial', 4.2), ('empty', 0.0),
        ])
        for url in (reverse('tracker'), reverse('book', args=['GEN'])):
            with self.subTest(url=url):
                page = self.client.get(url)
                self.assertContains(page, '--chapter-progress:25.8%')
                self.assertNotContains(page, '--chapter-progress:25,8%')
                self.assertContains(page, 'is-partial')
                self.assertContains(page, 'is-complete')
                self.assertContains(page, 'is-empty')
        self.assertContains(response, 'href="/tracker/GEN/?chapter=50"')
        self.assertContains(response, 'aria-label="Genesis 1: 8 van 31 verzen gelezen"')


class NoteRulesTests(TestCase):
    def make_note(self, refs, **extra):
        form = NoteForm({'body': 'Een gedachte bij deze passage.', 'references': refs, **extra})
        self.assertTrue(form.is_valid(), form.errors)
        return form.save()

    def test_all_four_link_types_and_tracker(self):
        theme = Theme.objects.create(name='Vertrouwen')
        plan = Plan.objects.create(title='Zeven dagen')
        study = Study.objects.create(title='Samen lezen')
        note = self.make_note('Johannes 3:16-18', themes=[theme.pk], plans=[plan.pk], studies=[study.pk])
        self.assertEqual(note.themes.get(), theme)
        self.assertEqual(note.plans.get(), plan)
        self.assertEqual(note.studies.get(), study)
        self.assertEqual(coverage()[('JHN', 3)], {16, 17, 18})

    def test_overlap_delete_and_edit(self):
        first = self.make_note('Johannes 3:16-18')
        second = self.make_note('Johannes 3:18-20')
        self.assertEqual(len(coverage()[('JHN', 3)]), 5)
        first.delete()
        self.assertEqual(coverage()[('JHN', 3)], {18, 19, 20})
        form = NoteForm({'body': 'Bijgewerkt', 'references': 'Johannes 3:21'}, instance=second)
        self.assertTrue(form.is_valid(), form.errors)
        form.save()
        self.assertEqual(coverage()[('JHN', 3)], {21})
        second.delete()
        self.assertEqual(coverage(), {})

    def test_whole_chapter_only_complete_when_all_verses_covered(self):
        self.make_note('Psalm 23:1-5')
        progress = book_progress(book_by_code('PSA'), coverage())
        self.assertEqual(progress['chapter_progress'][22]['state'], 'partial')
        self.make_note('Psalm 23:6')
        self.assertEqual(book_progress(book_by_code('PSA'), coverage())['chapter_progress'][22]['state'], 'complete')

    def test_theme_only_note_does_not_mark_plan_read(self):
        theme = Theme.objects.create(name='Genade')
        self.make_note('', themes=[theme.pk])
        self.assertEqual(coverage(), {})

    def test_empty_or_unlinked_notes_rejected(self):
        for data in [{'body': '  ', 'references': 'Johannes 3:16'}, {'body': 'Een gedachte'}, {'body': 'Een gedachte', 'references': 'Onbekend 1:1'}]:
            self.assertFalse(NoteForm(data).is_valid())
        self.assertEqual(Note.objects.count(), 0)
        self.assertEqual(Passage.objects.count(), 0)

    def test_reference_filters_include_overlap(self):
        self.make_note('Johannes 3:16-18')
        self.make_note('Johannes 3:18-20')
        response = self.client.get(reverse('notes'), {'book': 'JHN', 'chapter': 3, 'verse': 18})
        self.assertEqual(response.context['page'].paginator.count, 2)
        response = self.client.get(reverse('notes'), {'book': 'JHN', 'chapter': 3, 'verse': 16})
        self.assertEqual(response.context['page'].paginator.count, 1)

    def test_context_links_are_prefilled(self):
        for key, field, model, values in [('plan', 'plans', Plan, {'title': 'Plan'}), ('theme', 'themes', Theme, {'name': 'Hoop'}), ('study', 'studies', Study, {'title': 'Studie'})]:
            obj = model.objects.create(**values)
            response = self.client.get(reverse('note-new'), {key: obj.pk, 'references': 'Johannes 3:16'})
            self.assertEqual(response.context['form'].initial[field], [obj.pk])
            self.assertEqual(response.context['form'].initial['references'], 'Johannes 3:16')

    def test_markup_is_escaped(self):
        note = self.make_note('Johannes 3:16', body='<script>alert("x")</script>')
        response = self.client.get(reverse('note-detail', args=[note.pk]))
        self.assertNotContains(response, '<script>alert(')
        self.assertContains(response, '&lt;script&gt;')


class PlansStudiesSettingsTests(TestCase):
    def test_create_plan_edit_sessions_and_read_progress(self):
        response = self.client.post(reverse('plan-new'), {'title': 'Een week van hoop', 'days': 2})
        plan = Plan.objects.get()
        self.assertRedirects(response, reverse('plan-edit', args=[plan.pk]))
        sessions = list(plan.sessions.all())
        data = {'title': plan.title, 'description': 'Twee momenten', 'sessions-TOTAL_FORMS': 2, 'sessions-INITIAL_FORMS': 2, 'sessions-MIN_NUM_FORMS': 0, 'sessions-MAX_NUM_FORMS': 366}
        for i, session in enumerate(sessions):
            data.update({f'sessions-{i}-id': session.pk, f'sessions-{i}-plan': plan.pk, f'sessions-{i}-title': f'Dag {i+1}', f'sessions-{i}-references': 'Johannes 3:16-18' if i == 0 else 'Psalm 23', f'sessions-{i}-reflection': 'Wat valt je op?\nSchrijf je gedachten op.'})
        response = self.client.post(reverse('plan-edit', args=[plan.pk]), data)
        self.assertRedirects(response, reverse('plan-detail', args=[plan.pk]))
        self.assertEqual(sessions[0].passages.count(), 1)
        response = self.client.get(reverse('plan-detail', args=[plan.pk]))
        self.assertEqual(response.context['complete_count'], 0)
        form = NoteForm({'body': 'Een gedachte', 'references': 'Johannes 3:16-18', 'plans': [plan.pk]})
        self.assertTrue(form.is_valid(), form.errors)
        form.save()
        response = self.client.get(reverse('plan-detail', args=[plan.pk]))
        self.assertEqual(response.context['complete_count'], 1)
        self.assertIn(f'plan={plan.pk}', response.context['sessions'][0]['note_url'])

    def test_plan_invalid_day_prevents_partial_save(self):
        plan = Plan.objects.create(title='Origineel')
        session = PlanSession.objects.create(plan=plan, number=1)
        response = self.client.post(reverse('plan-edit', args=[plan.pk]), {'title': 'Gewijzigd', 'sessions-TOTAL_FORMS': 1, 'sessions-INITIAL_FORMS': 1, 'sessions-MIN_NUM_FORMS': 0, 'sessions-MAX_NUM_FORMS': 366, 'sessions-0-id': session.pk, 'sessions-0-plan': plan.pk, 'sessions-0-references': 'Johannes 999'})
        self.assertEqual(response.status_code, 200)
        plan.refresh_from_db()
        self.assertEqual(plan.title, 'Origineel')
        self.assertEqual(Passage.objects.count(), 0)

    def test_session_count_bounds(self):
        for days in (0, 367, 'bad'):
            self.client.post(reverse('plan-new'), {'title': 'Ongeldig', 'days': days})
        self.assertEqual(Plan.objects.count(), 0)

    def test_group_study_requires_group_and_solo_clears_group(self):
        group = Group.objects.create(name='Huiskring')
        form = StudyForm({'title': 'Studie', 'date': '2026-11-16', 'kind': 'group'})
        self.assertFalse(form.is_valid())
        form = StudyForm({'title': 'Studie', 'date': '2026-11-16', 'kind': 'group', 'group': group.pk})
        self.assertTrue(form.is_valid(), form.errors)
        study = form.save()
        self.assertEqual(study.group, group)
        response = self.client.post(reverse('delete', args=['group', group.pk]))
        self.assertEqual(response.status_code, 200)
        self.assertTrue(Group.objects.filter(pk=group.pk).exists())
        form = StudyForm({'title': 'Studie', 'date': '2026-11-16', 'kind': 'solo', 'group': group.pk}, instance=study)
        self.assertTrue(form.is_valid(), form.errors)
        self.assertIsNone(form.save().group)

    def test_toggle_preserves_notes_and_locks_versification(self):
        prefs = Preferences.current()
        form = NoteForm({'body': 'Een gedachte', 'references': 'Tobit 1:1'})
        self.assertTrue(form.is_valid(), form.errors)
        note = form.save()
        form = PreferencesForm({'deuterocanonical': True, 'versification': 'english'}, instance=prefs)
        self.assertTrue(form.is_valid(), form.errors)
        form.save()
        self.assertEqual(self.client.get(reverse('book', args=['TOB'])).status_code, 200)
        form = PreferencesForm({'deuterocanonical': False, 'versification': 'english'}, instance=prefs)
        self.assertTrue(form.is_valid(), form.errors)
        form.save()
        self.assertEqual(self.client.get(reverse('book', args=['TOB'])).status_code, 404)
        self.assertTrue(Note.objects.filter(pk=note.pk).exists())
        form = PreferencesForm({'versification': 'original'}, instance=prefs)
        self.assertFalse(form.is_valid())

    def test_plan_passages_also_lock_versification(self):
        prefs = Preferences.current()
        plan = Plan.objects.create(title='Plan')
        session = PlanSession.objects.create(plan=plan, number=1)
        session.passages.add(Passage.objects.create(book='GEN', chapter=1, start=1, end=3))
        form = PreferencesForm({'versification': 'original'}, instance=prefs)
        self.assertFalse(form.is_valid())

    def test_deleting_parent_preserves_notes(self):
        theme = Theme.objects.create(name='Hoop')
        note = Note.objects.create(body='Bewaar deze gedachte')
        note.themes.add(theme)
        self.client.post(reverse('delete', args=['theme', theme.pk]))
        self.assertTrue(Note.objects.filter(pk=note.pk).exists())
        self.assertEqual(note.themes.count(), 0)


class IntegrationTests(TestCase):
    def test_all_empty_pages_render_without_login(self):
        for name in ['home', 'tracker', 'notes', 'note-new', 'bundles', 'plans', 'plan-new', 'studies', 'study-new', 'themes', 'groups', 'settings', 'health']:
            with self.subTest(name=name):
                self.assertEqual(self.client.get(reverse(name)).status_code, 200)

    def test_bad_filters_return_404_not_server_errors(self):
        for url in ['/notities/?book=BOGUS', '/notities/?plan=wrong', '/tracker/GEN/?chapter=0', '/tracker/GEN/?chapter=bad', '/notities/?book=JHN&chapter=3&verse=99', '/studies/?group=bad']:
            self.assertEqual(self.client.get(url).status_code, 404, url)

    def test_csrf_and_safe_get_delete(self):
        note = Note.objects.create(body='Keep me')
        self.client.get(reverse('delete', args=['note', note.pk]))
        self.assertTrue(Note.objects.filter(pk=note.pk).exists())
        strict = Client(enforce_csrf_checks=True)
        self.assertEqual(strict.post(reverse('delete', args=['note', note.pk])).status_code, 403)
        self.assertEqual(strict.post(reverse('note-new'), {'body': 'Attack', 'references': 'Johannes 3:16'}).status_code, 403)

    def test_htmx_search_returns_fragment_and_normal_search_full_page(self):
        theme = Theme.objects.create(name='Hoop')
        note = Note.objects.create(body='Een hoopvolle gedachte')
        note.themes.add(theme)
        response = self.client.get(reverse('notes'), {'q': 'hoop'}, HTTP_HX_REQUEST='true', HTTP_HX_TARGET='note-results')
        self.assertContains(response, note.body)
        self.assertNotContains(response, '<html')
        self.assertContains(self.client.get(reverse('notes'), {'q': 'hoop'}), '<html')

    def test_export_roundtrip_preserves_all_links(self):
        Preferences.current()
        group = Group.objects.create(name='Huiskring')
        theme = Theme.objects.create(name='Hoop')
        study = Study.objects.create(title='Samen', kind='group', group=group)
        plan = Plan.objects.create(title='Plan')
        session = PlanSession.objects.create(plan=plan, number=1, reflection='Vraag')
        form = NoteForm({'body': 'Een gedachte', 'references': 'Johannes 3:16', 'themes': [theme.pk], 'plans': [plan.pk], 'studies': [study.pk]})
        self.assertTrue(form.is_valid(), form.errors)
        note = form.save()
        session.passages.set(note.passages.all())
        response = self.client.get(reverse('export'))
        data = response.content.decode()
        self.assertIn('attachment', response['Content-Disposition'])
        self.assertEqual(len(json.loads(data)), 8)
        Note.objects.all().delete()
        Plan.objects.all().delete()
        Study.objects.all().delete()
        Theme.objects.all().delete()
        Group.objects.all().delete()
        Passage.objects.all().delete()
        Preferences.objects.all().delete()
        for obj in serializers.deserialize('json', data):
            obj.save()
        restored = Note.objects.get()
        self.assertEqual(restored.themes.get().name, 'Hoop')
        self.assertEqual(restored.studies.get().group.name, 'Huiskring')
        self.assertEqual(restored.plans.get().sessions.get().passages.get(), restored.passages.get())
        self.assertEqual(coverage()[('JHN', 3)], {16})

    @override_settings(SECURE_SSL_REDIRECT=True)
    def test_health_remains_available_for_container_probe(self):
        self.assertEqual(self.client.get('/health/').status_code, 200)
        self.assertEqual(self.client.get('/').status_code, 301)

from django import forms
from django.forms import inlineformset_factory
from .models import Note, Plan, PlanSession, Study, Theme, Group, Preferences
from .bible import parse_passages, passage_objects


class ReferenceMixin:
    def init_references(self):
        self.prefs = Preferences.current()
        if self.instance.pk and 'references' not in self.initial:
            self.initial['references'] = '\n'.join(str(p) for p in self.instance.passages.all())
    def clean_references(self):
        value = self.cleaned_data.get('references', '')
        self.parsed = parse_passages(value, self.prefs)
        return value


def reference_field():
    return forms.CharField(label='Bijbelverwijzingen', required=False, widget=forms.Textarea(attrs={'rows': 3, 'placeholder': 'Johannes 3:16–18\nPsalm 23'}), help_text='Eén passage per regel, of gescheiden door een puntkomma. Hele hoofdstukken en bereiken zoals Genesis 1–3 zijn ook mogelijk.')


class NoteForm(ReferenceMixin, forms.ModelForm):
    references = reference_field()
    class Meta:
        model = Note
        fields = ['title', 'body', 'references', 'plans', 'themes', 'studies']
        widgets = {'body': forms.Textarea(attrs={'rows': 12, 'placeholder': 'Wat valt je op? Wat neem je mee?'}), 'plans': forms.CheckboxSelectMultiple, 'themes': forms.CheckboxSelectMultiple, 'studies': forms.CheckboxSelectMultiple}
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.init_references()
    def clean(self):
        data = super().clean()
        if not any(data.get(k) for k in ('references', 'plans', 'themes', 'studies')):
            raise forms.ValidationError('Koppel je notitie aan minstens één Bijbeltekst, leesplan, thema of studie.')
        return data
    def save(self, commit=True):
        instance = super().save(commit=commit)
        if commit:
            instance.passages.set(passage_objects(self.parsed))
        return instance


class PlanForm(forms.ModelForm):
    days = forms.IntegerField(label='Aantal dagen / sessies', min_value=1, max_value=366, initial=7)
    class Meta:
        model = Plan
        fields = ['title', 'description', 'days']
        widgets = {'description': forms.Textarea(attrs={'rows': 3})}


class PlanMetaForm(forms.ModelForm):
    class Meta:
        model = Plan
        fields = ['title', 'description']
        widgets = {'description': forms.Textarea(attrs={'rows': 3})}


class SessionForm(ReferenceMixin, forms.ModelForm):
    references = reference_field()
    class Meta:
        model = PlanSession
        fields = ['title', 'references', 'reflection']
        widgets = {'reflection': forms.Textarea(attrs={'rows': 7, 'placeholder': 'Plak hier je overdenking of vragen voor deze sessie.'})}
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.init_references()
    def save(self, commit=True):
        instance = super().save(commit=commit)
        if commit:
            instance.passages.set(passage_objects(self.parsed))
        return instance


SessionFormSet = inlineformset_factory(Plan, PlanSession, form=SessionForm, extra=0, can_delete=False, max_num=366, validate_max=True)


class StudyForm(forms.ModelForm):
    class Meta:
        model = Study
        fields = ['title', 'date', 'kind', 'group']
        widgets = {'date': forms.DateInput(format='%Y-%m-%d', attrs={'type': 'date'}), 'kind': forms.RadioSelect}
    def clean(self):
        data = super().clean()
        if data.get('kind') == 'group' and not data.get('group'):
            self.add_error('group', 'Kies de groep waarmee je de studie hebt gedaan. Maak die zo nodig eerst aan bij Groepen.')
        if data.get('kind') == 'solo':
            data['group'] = None
        return data


class ThemeForm(forms.ModelForm):
    class Meta:
        model = Theme
        fields = ['name', 'description']
        widgets = {'description': forms.Textarea(attrs={'rows': 3})}


class GroupForm(forms.ModelForm):
    class Meta:
        model = Group
        fields = ['name']


class PreferencesForm(forms.ModelForm):
    class Meta:
        model = Preferences
        fields = ['deuterocanonical', 'versification']
    def clean_versification(self):
        scheme = self.cleaned_data['versification']
        if scheme != self.instance.versification:
            from .models import Passage
            if Passage.objects.filter(notes__isnull=False).exists() or Passage.objects.filter(plansession__isnull=False).exists():
                raise forms.ValidationError('De versindeling kan niet worden gewijzigd zodra passages zijn vastgelegd. Zo blijven je bestaande verwijzingen correct. Kies de indeling vóór je eerste notitie of leesplanpassage.')
        return scheme

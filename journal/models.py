from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.utils import timezone


class Preferences(models.Model):
    deuterocanonical = models.BooleanField(default=False, verbose_name='Deuterocanonieke boeken tonen')
    versification = models.CharField(max_length=12, default='english', choices=[('english', 'Engelse versindeling'), ('original', 'Hebreeuwse versindeling (Oude Testament)')], verbose_name='Hoofdstuk- en versindeling')

    @classmethod
    def current(cls):
        return cls.objects.get_or_create(pk=1)[0]


class Group(models.Model):
    name = models.CharField(max_length=100, unique=True, verbose_name='Groepsnaam')
    class Meta:
        ordering = ['name']
    def __str__(self):
        return self.name


class Theme(models.Model):
    name = models.CharField(max_length=100, unique=True, verbose_name='Thema')
    description = models.TextField(blank=True, verbose_name='Omschrijving')
    class Meta:
        ordering = ['name']
    def __str__(self):
        return self.name


class Passage(models.Model):
    book = models.CharField(max_length=4)
    chapter = models.PositiveSmallIntegerField()
    start = models.PositiveSmallIntegerField()
    end = models.PositiveSmallIntegerField()
    class Meta:
        ordering = ['book', 'chapter', 'start', 'end']
        constraints = [models.UniqueConstraint(fields=['book', 'chapter', 'start', 'end'], name='unique_passage'), models.CheckConstraint(condition=models.Q(chapter__gte=1, start__gte=1, end__gte=models.F('start')), name='valid_passage')]
    def __str__(self):
        from .bible import book_by_code
        book = book_by_code(self.book)
        span = str(self.start) if self.start == self.end else f'{self.start}–{self.end}'
        return f'{book["name"]} {self.chapter}:{span}'


class Plan(models.Model):
    title = models.CharField(max_length=160, verbose_name='Naam van je leesplan')
    description = models.TextField(blank=True, verbose_name='Omschrijving')
    created = models.DateTimeField(auto_now_add=True)
    class Meta:
        ordering = ['-created']
    def __str__(self):
        return self.title


class PlanSession(models.Model):
    plan = models.ForeignKey(Plan, related_name='sessions', on_delete=models.CASCADE)
    number = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(366)])
    title = models.CharField(max_length=160, blank=True, verbose_name='Titel (optioneel)')
    passages = models.ManyToManyField(Passage, blank=True)
    reflection = models.TextField(blank=True, verbose_name='Overdenking en vragen')
    class Meta:
        ordering = ['number']
        constraints = [models.UniqueConstraint(fields=['plan', 'number'], name='unique_session')]


class Study(models.Model):
    title = models.CharField(max_length=160, verbose_name='Titel')
    date = models.DateField(default=timezone.localdate, verbose_name='Datum')
    kind = models.CharField(max_length=5, choices=[('solo', 'Solo'), ('group', 'Met een groep')], default='solo', verbose_name='Soort studie')
    group = models.ForeignKey(Group, null=True, blank=True, on_delete=models.PROTECT, verbose_name='Groep')
    class Meta:
        ordering = ['-date', '-pk']
        constraints = [models.CheckConstraint(condition=models.Q(kind='solo', group__isnull=True) | models.Q(kind='group', group__isnull=False), name='study_group_required')]
    def __str__(self):
        return self.title


class Note(models.Model):
    title = models.CharField(max_length=160, blank=True, verbose_name='Titel (optioneel)')
    body = models.TextField(verbose_name='Je notitie')
    passages = models.ManyToManyField(Passage, related_name='notes', blank=True)
    plans = models.ManyToManyField(Plan, related_name='notes', blank=True, verbose_name='Leesplannen')
    themes = models.ManyToManyField(Theme, related_name='notes', blank=True, verbose_name='Thema’s')
    studies = models.ManyToManyField(Study, related_name='notes', blank=True, verbose_name='Bijbelstudies')
    created = models.DateTimeField(auto_now_add=True)
    updated = models.DateTimeField(auto_now=True)
    class Meta:
        ordering = ['-updated', '-pk']
    def __str__(self):
        return self.title or self.body[:65]

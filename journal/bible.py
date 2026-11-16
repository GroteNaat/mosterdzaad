"""Alleen versmetadata en verwijzingen; bevat geen Bijbelteksten."""
import json
import re
from functools import lru_cache
from pathlib import Path
from django.core.exceptions import ValidationError


@lru_cache(maxsize=2)
def books(scheme='english'):
    filename = 'books-original.json' if scheme == 'original' else 'books.json'
    return json.loads((Path(__file__).parent / 'data' / filename).read_text(encoding='utf-8'))


def book_by_code(code, scheme='english'):
    return next(b for b in books(scheme) if b['code'] == code)


def visible_books(prefs):
    return [b for b in books(prefs.versification) if prefs.deuterocanonical or b['testament'] != 'DC']


def normalize(value):
    return re.sub(r'[\s.]+', '', value.casefold())


def parse_passages(text, prefs):
    """Normalize chapter / verse ranges to one tuple per chapter, atomically."""
    lookup = {}
    # Hidden books remain editable in existing notes, but are not shown in tracker.
    for book in books(prefs.versification):
        for alias in [book['code'], book['name'], *book.get('aliases', [])]:
            lookup[normalize(alias)] = book
    result = []
    for raw in re.split(r'[;\n]+', text.strip()):
        raw = raw.strip().replace('–', '-').replace('—', '-')
        if not raw:
            continue
        match = re.fullmatch(r'(.+?)\s+(\d+)(?::(\d+))?(?:\s*-\s*(\d+)(?::(\d+))?)?', raw)
        if not match:
            raise ValidationError(f'Onbekende verwijzing: “{raw}”. Gebruik bijvoorbeeld Johannes 3:16-18; Psalm 23.')
        name, ch, vs, last, last_vs = match.groups()
        book = lookup.get(normalize(name))
        if not book:
            raise ValidationError(f'Onbekend Bijbelboek: “{name}”. Gebruik de volledige boeknaam.')
        start_ch, start_v = int(ch), int(vs or 1)
        if vs and last and not last_vs:
            end_ch, end_v = start_ch, int(last)
        elif vs:
            end_ch, end_v = int(last or ch), int(last_vs or vs)
        else:
            if last_vs:
                raise ValidationError('Gebruik bij een bereik met verzen aan beide kanten een hoofdstuk en vers.')
            end_ch, end_v = int(last or ch), None
        counts = book['chapters']
        if not (1 <= start_ch <= end_ch <= len(counts)):
            raise ValidationError(f'{book["name"]} heeft {len(counts)} hoofdstukken; controleer “{raw}”.')
        end_v = end_v if end_v is not None else counts[end_ch - 1]
        if not (1 <= start_v <= counts[start_ch - 1] and 1 <= end_v <= counts[end_ch - 1]) or (start_ch == end_ch and end_v < start_v):
            raise ValidationError(f'Ongeldig versbereik in “{raw}”. Controleer de gekozen versindeling bij Instellingen.')
        for chapter in range(start_ch, end_ch + 1):
            result.append((book['code'], chapter, start_v if chapter == start_ch else 1, end_v if chapter == end_ch else counts[chapter - 1]))
    return list(dict.fromkeys(result))


def passage_objects(parsed):
    from .models import Passage
    return [Passage.objects.get_or_create(book=b, chapter=c, start=s, end=e)[0] for b, c, s, e in parsed]


def coverage():
    from .models import Passage
    covered = {}
    for book, chapter, start, end in Passage.objects.filter(notes__isnull=False).values_list('book', 'chapter', 'start', 'end').distinct():
        covered.setdefault((book, chapter), set()).update(range(start, end + 1))
    return covered


def book_progress(book, covered):
    chapters = []
    for number, total in enumerate(book['chapters'], 1):
        read = len(covered.get((book['code'], number), set()) & set(range(1, total + 1)))
        chapters.append({'number': number, 'total': total, 'read': read, 'state': 'complete' if read == total else 'partial' if read else 'empty'})
    read, total = sum(c['read'] for c in chapters), sum(book['chapters'])
    return {**book, 'chapter_progress': chapters, 'read': read, 'total': total, 'percent': round(100 * read / total, 1), 'complete_chapters': sum(c['state'] == 'complete' for c in chapters)}

# Lesson 23 – Homework: Python Part 2 (Text Analyzer & Address Book)


## Homework 1: Text Analyzer (`text_analyzer.py`)

### What it does

Reads a line of text from the user and prints:

- character count (with and without spaces),
- word count (punctuation ignored),
- sentence count (sentences end with `.`, `!` or `?`),
- the longest word,
- the most frequent word(s) — case-insensitive, with ties reported together.

### Design decisions

- **Punctuation handling** – each word is passed through `word.strip(".,!?;:()\"'")`, which removes punctuation from word edges without touching characters inside a word.
- **Case-insensitivity** – the whole text is lowercased before counting, so `Kot` and `kot` count as the same word.
- **Frequency counting** – a plain dictionary with `counts.get(word, 0) + 1`, i.e. exactly the dict pattern from this lesson (no `collections.Counter` yet).
- **Ties** – `most_common_words()` returns *all* words that reach the maximum count, per the requirement "word or words".
- **Sentence counting** – a simple loop counting occurrences of `.`, `!`, `?`.

### Test run

```
Podaj tekst do analizy: Ala ma kota. Kot ma Ale! Czy kot lubi mleko? Kot to kot.

Liczba znakow (ze spacjami): 56
Liczba znakow (bez spacji):  44
Liczba slow:                 13
Liczba zdan:                 4
Najdluzsze slowo:            mleko
Najczestsze slowo(a):        kot (x4)
```

`kot` correctly counted 4 times — case folding merged `Kot`/`kot`, and stripping merged `kot.` with `kot`.

## Homework 2: Address Book (`address_book.py`)

### What it does

An interactive menu-driven address book:

```
--- KSIAZKA ADRESOWA ---
1. Dodaj kontakt
2. Wyswietl wszystkie
3. Szukaj
4. Edytuj kontakt
5. Usun kontakt
0. Wyjscie
```

### Design decisions

- **Storage** – a dictionary `contacts` keyed by a unique auto-incremented integer ID (`next_id`), per the requirement. Each value is itself a dict with `imie`, `nazwisko`, `telefon`, `email` — a nested-dictionary structure straight from this lesson.
- **Validation**:
  - phone: `phone.isdigit()` and at least 7 digits — rejects letters, spaces and dashes,
  - email: must contain `@` and a dot in the domain part,
  - first/last name: must be non-empty.
  Invalid input aborts the operation with a message instead of storing bad data.
- **Search** – case-insensitive substring match against first *or* last name, so `bar` finds `Bartek`.
- **Edit** – shows the current contact, then re-asks for all fields and stores them under the same ID (ID stability preserved).
- **Shared helpers** – `ask_contact_data()` is reused by add and edit; `get_existing_id()` centralizes ID validation for edit and delete.

### Test run (fragment)

```
Wybierz opcje: 1
Imie: bartek
Nazwisko: ads
Telefon (same cyfry): 123456
Nieprawidlowy telefon - wymagane minimum 7 cyfr, bez innych znakow.

Wybierz opcje: 1
...
Telefon (same cyfry): 1234567
Email: asd@wp.pl
Dodano kontakt (ID: 1).

Wybierz opcje: 2
[1] bartek fwefew | tel: 1234567 | email: asd@wp.pl
```

Verified interactively: phone validation rejects too-short numbers, add/list/search/edit/delete all work, empty book prints a friendly message.

## Conclusions

- A plain dict covers both counting (analyzer) and record storage (address book) — the two most common dictionary patterns.
- Validating input *before* mutating state keeps the data structure consistent; helper functions returning `None` on invalid input make the calling code trivial.
- `str.strip(chars)` removes characters only from the edges — the right tool for punctuation attached to words (vs `replace`, which would also hit characters inside words).
- Advanced-criteria items used: list comprehension (tie detection in the analyzer), nested data structures (dicts of dicts), input error handling.
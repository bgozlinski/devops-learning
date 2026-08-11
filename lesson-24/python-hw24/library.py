class Ksiazka:
    def __init__(self, tytul, autor, isbn, rok):
        self.tytul = tytul
        self.autor = autor
        self.isbn = isbn
        self.rok = rok
        self.dostepna = True

    def info(self):
        status = "dostepna" if self.dostepna else "wypozyczona"
        return f"'{self.tytul}' - {self.autor} ({self.rok}) [ISBN: {self.isbn}] - {status}"


class Czytelnik:
    def __init__(self, imie, nazwisko, numer):
        self.imie = imie
        self.nazwisko = nazwisko
        self.numer = numer
        self.__wypozyczone = []  # enkapsulacja - dostep tylko przez metody

    def wypozycz(self, ksiazka):
        self.__wypozyczone.append(ksiazka)

    def zwroc(self, ksiazka):
        self.__wypozyczone.remove(ksiazka)

    def lista_wypozyczonych(self):
        return list(self.__wypozyczone)  # kopia, nie oryginal

    def info(self):
        return f"[{self.numer}] {self.imie} {self.nazwisko}, wypozyczonych ksiazek: {len(self.__wypozyczone)}"


class Biblioteka:
    def __init__(self, nazwa, adres):
        self.nazwa = nazwa
        self.adres = adres
        self.__ksiazki = []      # enkapsulacja kolekcji
        self.__czytelnicy = []

    # --- zarzadzanie ksiazkami ---
    def dodaj_ksiazke(self, ksiazka):
        self.__ksiazki.append(ksiazka)
        print(f"Dodano: {ksiazka.info()}")

    def usun_ksiazke(self, isbn):
        ksiazka = self.znajdz_po_isbn(isbn)
        if ksiazka and ksiazka.dostepna:
            self.__ksiazki.remove(ksiazka)
            print(f"Usunieto ksiazke ISBN {isbn}.")
        else:
            print(f"Nie mozna usunac - ksiazka nie istnieje lub jest wypozyczona.")

    # --- zarzadzanie czytelnikami ---
    def zarejestruj_czytelnika(self, czytelnik):
        self.__czytelnicy.append(czytelnik)
        print(f"Zarejestrowano: {czytelnik.info()}")

    def znajdz_czytelnika(self, numer):
        for czytelnik in self.__czytelnicy:
            if czytelnik.numer == numer:
                return czytelnik
        return None

    # --- wyszukiwanie ---
    def znajdz_po_isbn(self, isbn):
        for ksiazka in self.__ksiazki:
            if ksiazka.isbn == isbn:
                return ksiazka
        return None

    def szukaj(self, fraza):
        """Szuka po tytule, autorze lub ISBN (case-insensitive)."""
        fraza = fraza.lower()
        wyniki = []
        for ksiazka in self.__ksiazki:
            if (fraza in ksiazka.tytul.lower()
                    or fraza in ksiazka.autor.lower()
                    or fraza in ksiazka.isbn.lower()):
                wyniki.append(ksiazka)
        return wyniki

    # --- wypozyczenia ---
    def wypozycz(self, isbn, numer_czytelnika):
        ksiazka = self.znajdz_po_isbn(isbn)
        czytelnik = self.znajdz_czytelnika(numer_czytelnika)

        if ksiazka is None or czytelnik is None:
            print("Nie znaleziono ksiazki lub czytelnika.")
            return
        if not ksiazka.dostepna:
            print(f"'{ksiazka.tytul}' jest juz wypozyczona.")
            return

        ksiazka.dostepna = False
        czytelnik.wypozycz(ksiazka)
        print(f"{czytelnik.imie} {czytelnik.nazwisko} wypozyczyl(a) '{ksiazka.tytul}'.")

    def zwroc(self, isbn, numer_czytelnika):
        ksiazka = self.znajdz_po_isbn(isbn)
        czytelnik = self.znajdz_czytelnika(numer_czytelnika)

        if ksiazka is None or czytelnik is None:
            print("Nie znaleziono ksiazki lub czytelnika.")
            return
        if ksiazka not in czytelnik.lista_wypozyczonych():
            print(f"Ten czytelnik nie ma wypozyczonej '{ksiazka.tytul}'.")
            return

        ksiazka.dostepna = True
        czytelnik.zwroc(ksiazka)
        print(f"{czytelnik.imie} {czytelnik.nazwisko} zwrocil(a) '{ksiazka.tytul}'.")

    def stan_czytelnika(self, numer):
        czytelnik = self.znajdz_czytelnika(numer)
        if czytelnik is None:
            print("Nie znaleziono czytelnika.")
            return
        print(czytelnik.info())
        for ksiazka in czytelnik.lista_wypozyczonych():
            print(f"  - {ksiazka.info()}")


if __name__ == "__main__":
    bib = Biblioteka("Biblioteka Miejska", "ul. Glowna 1, Warszawa")

    print("=== Dodawanie ksiazek ===")
    bib.dodaj_ksiazke(Ksiazka("Hobbit", "J.R.R. Tolkien", "978-0261102217", 1937))
    bib.dodaj_ksiazke(Ksiazka("Wiedzmin", "Andrzej Sapkowski", "978-8375780635", 1990))
    bib.dodaj_ksiazke(Ksiazka("Diuna", "Frank Herbert", "978-8324589562", 1965))

    print("\n=== Rejestracja czytelnikow ===")
    bib.zarejestruj_czytelnika(Czytelnik("Jan", "Kowalski", 1))
    bib.zarejestruj_czytelnika(Czytelnik("Anna", "Nowak", 2))

    print("\n=== Wyszukiwanie ===")
    for ksiazka in bib.szukaj("tolkien"):
        print(ksiazka.info())

    print("\n=== Wypozyczenia ===")
    bib.wypozycz("978-0261102217", 1)
    bib.wypozycz("978-0261102217", 2)   # proba wypozyczenia zajetej
    bib.wypozycz("978-8375780635", 2)

    print("\n=== Stan czytelnikow ===")
    bib.stan_czytelnika(1)
    bib.stan_czytelnika(2)

    print("\n=== Zwrot i usuwanie ===")
    bib.usun_ksiazke("978-0261102217")  # proba usuniecia wypozyczonej
    bib.zwroc("978-0261102217", 1)
    bib.usun_ksiazke("978-0261102217")  # teraz sie uda

    print("\n=== Enkapsulacja ===")
    try:
        print(bib.__ksiazki)
    except AttributeError as e:
        print(f"Blad przy bezposrednim dostepie: {e}")

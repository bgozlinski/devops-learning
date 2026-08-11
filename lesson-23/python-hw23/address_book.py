contacts = {}
next_id = 1


def is_valid_phone(phone):
    return phone.isdigit() and len(phone) >= 7


def is_valid_email(email):
    return "@" in email and "." in email.split("@")[-1]


def ask_contact_data():
    """Pyta o dane kontaktu z walidacja. Zwraca slownik lub None."""
    first_name = input("Imie: ").strip()
    last_name = input("Nazwisko: ").strip()
    if not first_name or not last_name:
        print("Imie i nazwisko nie moga byc puste.")
        return None

    phone = input("Telefon (same cyfry): ").strip()
    if not is_valid_phone(phone):
        print("Nieprawidlowy telefon - wymagane minimum 7 cyfr, bez innych znakow.")
        return None

    email = input("Email: ").strip()
    if not is_valid_email(email):
        print("Nieprawidlowy email.")
        return None

    return {"imie": first_name, "nazwisko": last_name, "telefon": phone, "email": email}


def add_contact():
    global next_id
    data = ask_contact_data()
    if data:
        contacts[next_id] = data
        print(f"Dodano kontakt (ID: {next_id}).")
        next_id += 1


def show_contact(contact_id):
    c = contacts[contact_id]
    print(f"[{contact_id}] {c['imie']} {c['nazwisko']} | tel: {c['telefon']} | email: {c['email']}")


def show_all():
    if not contacts:
        print("Ksiazka adresowa jest pusta.")
        return
    for contact_id in sorted(contacts):
        show_contact(contact_id)


def search_contacts():
    query = input("Szukaj (imie lub nazwisko): ").strip().lower()
    found = False
    for contact_id, c in contacts.items():
        if query in c["imie"].lower() or query in c["nazwisko"].lower():
            show_contact(contact_id)
            found = True
    if not found:
        print("Nie znaleziono kontaktow.")


def get_existing_id():
    """Pyta o ID i zwraca je jako int, albo None gdy bledne/nieistniejace."""
    raw = input("Podaj ID kontaktu: ").strip()
    if not raw.isdigit() or int(raw) not in contacts:
        print("Nie ma kontaktu o takim ID.")
        return None
    return int(raw)


def delete_contact():
    contact_id = get_existing_id()
    if contact_id is not None:
        del contacts[contact_id]
        print(f"Usunieto kontakt {contact_id}.")


def edit_contact():
    contact_id = get_existing_id()
    if contact_id is None:
        return
    show_contact(contact_id)
    print("Podaj nowe dane:")
    data = ask_contact_data()
    if data:
        contacts[contact_id] = data
        print(f"Zaktualizowano kontakt {contact_id}.")


def main():
    menu = """
--- KSIAZKA ADRESOWA ---
1. Dodaj kontakt
2. Wyswietl wszystkie
3. Szukaj
4. Edytuj kontakt
5. Usun kontakt
0. Wyjscie"""

    while True:
        print(menu)
        choice = input("Wybierz opcje: ").strip()
        if choice == "1":
            add_contact()
        elif choice == "2":
            show_all()
        elif choice == "3":
            search_contacts()
        elif choice == "4":
            edit_contact()
        elif choice == "5":
            delete_contact()
        elif choice == "0":
            print("Do zobaczenia!")
            break
        else:
            print("Nieznana opcja.")


if __name__ == "__main__":
    main()

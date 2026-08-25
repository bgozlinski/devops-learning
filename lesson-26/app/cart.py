"""Prosta logika koszyka zakupowego - kod budowany i testowany przez pipeline."""

VAT_RATE = 0.23

DISCOUNT_CODES = {
    "DEVOPS10": 0.10,
    "JENKINS20": 0.20,
}


def new_cart():
    """Zwraca pusty koszyk (lista pozycji)."""
    return []


def add_item(cart, name, price, quantity=1):
    """Dodaje pozycje do koszyka. Rzuca ValueError dla nieprawidlowych danych."""
    if not name:
        raise ValueError("Nazwa produktu nie moze byc pusta.")
    if price < 0:
        raise ValueError("Cena nie moze byc ujemna.")
    if quantity < 1:
        raise ValueError("Ilosc musi byc wieksza od zera.")

    # Ta sama pozycja dodana ponownie zwieksza tylko ilosc.
    for item in cart:
        if item["name"] == name and item["price"] == price:
            item["quantity"] += quantity
            return cart

    cart.append({"name": name, "price": price, "quantity": quantity})
    return cart


def remove_item(cart, name):
    """Usuwa wszystkie pozycje o podanej nazwie. Zwraca liczbe usunietych pozycji."""
    before = len(cart)
    cart[:] = [item for item in cart if item["name"] != name]
    return before - len(cart)


def subtotal(cart):
    """Suma netto koszyka."""
    return round(sum(item["price"] * item["quantity"] for item in cart), 2)


def apply_discount(amount, code):
    """Nalicza rabat wg kodu. Nieznany kod nie zmienia kwoty."""
    rate = DISCOUNT_CODES.get(code.upper() if code else "", 0.0)
    return round(amount * (1 - rate), 2)


def total_with_vat(cart, code=None):
    """Kwota brutto koszyka po rabacie."""
    return round(apply_discount(subtotal(cart), code) * (1 + VAT_RATE), 2)


def summary(cart, code=None):
    """Tekstowe podsumowanie koszyka - uzywane przez smoke test po wdrozeniu."""
    lines = [f"{i['quantity']} x {i['name']} @ {i['price']:.2f}" for i in cart]
    lines.append(f"netto: {subtotal(cart):.2f}")
    lines.append(f"brutto: {total_with_vat(cart, code):.2f}")
    return "\n".join(lines)


if __name__ == "__main__":
    demo = new_cart()
    add_item(demo, "Klawiatura", 199.99)
    add_item(demo, "Mysz", 89.50, 2)
    print(summary(demo, "DEVOPS10"))

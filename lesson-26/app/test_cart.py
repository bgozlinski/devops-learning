import pytest

from cart import (
    add_item,
    apply_discount,
    new_cart,
    remove_item,
    subtotal,
    summary,
    total_with_vat,
)


def test_new_cart_is_empty():
    assert new_cart() == []


def test_add_item():
    cart = add_item(new_cart(), "Mysz", 89.50)
    assert cart == [{"name": "Mysz", "price": 89.50, "quantity": 1}]


def test_add_same_item_twice_increases_quantity():
    cart = new_cart()
    add_item(cart, "Mysz", 89.50)
    add_item(cart, "Mysz", 89.50, 2)
    assert len(cart) == 1
    assert cart[0]["quantity"] == 3


def test_add_item_rejects_empty_name():
    with pytest.raises(ValueError):
        add_item(new_cart(), "", 10.0)


def test_add_item_rejects_negative_price():
    with pytest.raises(ValueError):
        add_item(new_cart(), "Mysz", -1.0)


def test_add_item_rejects_zero_quantity():
    with pytest.raises(ValueError):
        add_item(new_cart(), "Mysz", 10.0, 0)


def test_remove_item():
    cart = new_cart()
    add_item(cart, "Mysz", 89.50)
    add_item(cart, "Klawiatura", 199.99)
    assert remove_item(cart, "Mysz") == 1
    assert len(cart) == 1


def test_remove_missing_item_returns_zero():
    assert remove_item(new_cart(), "Monitor") == 0


def test_subtotal():
    cart = new_cart()
    add_item(cart, "Mysz", 100.0, 2)
    add_item(cart, "Klawiatura", 50.0)
    assert subtotal(cart) == 250.0


def test_apply_known_discount():
    assert apply_discount(100.0, "DEVOPS10") == 90.0


def test_apply_discount_is_case_insensitive():
    assert apply_discount(100.0, "jenkins20") == 80.0


def test_apply_unknown_discount_changes_nothing():
    assert apply_discount(100.0, "NOPE") == 100.0
    assert apply_discount(100.0, None) == 100.0


def test_total_with_vat():
    cart = add_item(new_cart(), "Mysz", 100.0)
    assert total_with_vat(cart) == 123.0


def test_total_with_vat_and_discount():
    cart = add_item(new_cart(), "Mysz", 100.0)
    assert total_with_vat(cart, "DEVOPS10") == 110.7


def test_summary_contains_totals():
    cart = add_item(new_cart(), "Mysz", 100.0)
    text = summary(cart)
    assert "netto: 100.00" in text
    assert "brutto: 123.00" in text

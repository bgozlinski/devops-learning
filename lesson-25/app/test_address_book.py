from address_book import is_valid_phone, is_valid_email


def test_valid_phone():
    assert is_valid_phone("123456789")


def test_phone_too_short():
    assert not is_valid_phone("123456")


def test_phone_with_letters():
    assert not is_valid_phone("12345abc")


def test_valid_email():
    assert is_valid_email("bartek@example.com")


def test_email_without_at():
    assert not is_valid_email("bartek.example.com")


def test_email_without_domain_dot():
    assert not is_valid_email("bartek@example")

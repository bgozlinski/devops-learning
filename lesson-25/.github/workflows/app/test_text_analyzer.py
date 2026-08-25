from text_analyzer import clean_words, count_sentences, most_common_words


def test_clean_words_strips_punctuation_and_lowercases():
    assert clean_words("Hello, World! Hello.") == ["hello", "world", "hello"]


def test_clean_words_skips_empty_tokens():
    assert clean_words("... ,,, ok") == ["ok"]


def test_count_sentences():
    assert count_sentences("One. Two! Three? Four") == 3


def test_most_common_words_single_winner():
    common, count = most_common_words(["a", "b", "a"])
    assert common == ["a"] and count == 2


def test_most_common_words_tie():
    common, count = most_common_words(["x", "y"])
    assert sorted(common) == ["x", "y"] and count == 1

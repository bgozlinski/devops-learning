def clean_words(text):
    """Zwraca liste slow bez interpunkcji, malymi literami."""
    words = []
    for word in text.lower().split():
        cleaned = word.strip(".,!?;:()\"'")
        if cleaned:
            words.append(cleaned)
    return words


def count_sentences(text):
    count = 0
    for char in text:
        if char in ".!?":
            count += 1
    return count


def most_common_words(words):
    counts = {}
    for word in words:
        counts[word] = counts.get(word, 0) + 1
    max_count = max(counts.values())
    common = [word for word, count in counts.items() if count == max_count]
    return common, max_count


def main():
    text = input("Podaj tekst do analizy: ")

    if not text.strip():
        print("Nie podano tekstu.")
        return

    words = clean_words(text)
    longest = max(words, key=len)
    common, max_count = most_common_words(words)

    print(f"\nLiczba znakow (ze spacjami): {len(text)}")
    print(f"Liczba znakow (bez spacji):  {len(text.replace(' ', ''))}")
    print(f"Liczba slow:                 {len(words)}")
    print(f"Liczba zdan:                 {count_sentences(text)}")
    print(f"Najdluzsze slowo:            {longest}")
    print(f"Najczestsze slowo(a):        {', '.join(common)} (x{max_count})")


if __name__ == "__main__":
    main()

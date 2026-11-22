import re
import unicodedata


def normalize(value):
    normalized = unicodedata.normalize("NFC", value).casefold().translate(
        str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")
    )
    return " ".join(re.findall(r"[\w\u0980-\u09ff]+", normalized.replace("\u200c", "").replace("\u200d", "")))


def one_edit(word, candidate):
    if len(word) < 4 or abs(len(word) - len(candidate)) > 1:
        return False
    if len(word) == len(candidate):
        return sum(a != b for a, b in zip(word, candidate)) <= 1
    short, long = sorted((word, candidate), key=len)
    index = next((i for i, (a, b) in enumerate(zip(short, long)) if a != b), len(short))
    return short[index:] == long[index + 1:]


def matches(book, query):
    fields = ("official_title", "alternative_title", "subject_en", "subject_bn",
              "class_en", "class_bn", "academic_year", "curriculum_track", "edition")
    class_id = book["class_id"]
    last_class = book.get("class_end_id") or class_id
    grades = " ".join(str(grade) for grade in range(class_id, last_class + 1))
    metadata = " ".join(str(book.get(field) or "") for field in fields)
    haystack = normalize(f"{metadata} {grades}")
    return all(term in haystack or any(one_edit(term, word) for word in haystack.split())
               for term in normalize(query).split())

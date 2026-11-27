"""Extract a short subject from an approved exchange."""

import re

LEADING = {"a", "an", "about", "can", "could", "describe", "explain", "give", "how", "i",
           "exactly", "is", "me", "please", "reply", "show", "tell", "the", "to", "what", "with",
           "word", "would", "you"}


def subject_title(prompt, answer):
    words = re.findall(r"[^\W_]+(?:[-'][^\W_]+)*", prompt.partition("\n")[0])
    start = next((i for i, word in enumerate(words) if word.casefold() not in LEADING), len(words))
    subject = words[start:start + 7]
    if not subject:
        subject = re.findall(r"[^\W_]+", answer)[:5]
    return " ".join(subject)[:80].strip()

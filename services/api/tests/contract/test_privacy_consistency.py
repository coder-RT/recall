"""The privacy note exists three times (docs/privacy.md, the website, the iPhone app) and the Mac's /privacy lists the
same rows: they must say the same thing, word for word, so none of them drifts into a promise the others don't make."""

import re
from pathlib import Path

from recall_api.application.describe_privacy import describe_privacy

ROOT = Path(__file__).resolve().parents[4]
DOC = (ROOT / "docs" / "privacy.md").read_text()
WEB = (ROOT / "apps" / "web" / "i18n" / "dictionaries" / "en.ts").read_text()
APP = (
    ROOT / "apps" / "ios" / "Packages" / "RecallKit" / "Sources" / "RecallDomain" / "Setup" / "Privacy.swift"
).read_text()


def flat(text: str) -> str:
    """Markdown and source code without line breaks, emphasis or string concatenation, for comparing sentences."""
    text = re.sub(r'"\s*\+\s*"', "", text)  # Swift "a " + "b"
    text = re.sub(r"\s*\n\s*", " ", text)
    return text.replace("**", "").replace("\\'", "'").replace("’", "'")


def test_every_row_the_mac_reports_is_in_the_doc_and_on_the_website():
    flows = describe_privacy("baseten_spark_open", "baseten_spark_open", "local", True, 90).sent
    for f in flows:
        assert f.what in flat(DOC), f.what
        assert f.what in flat(WEB), f.what


def test_the_never_list_is_the_same_everywhere():
    never = re.search(r"## Never\n\n(.*?)\n\n##", DOC, re.S).group(1)
    lines = [flat(line.removeprefix("- ")) for line in never.split("\n- ")]
    assert len(lines) == 3
    for line in lines:
        assert line in flat(WEB), line
        assert line in flat(APP), line

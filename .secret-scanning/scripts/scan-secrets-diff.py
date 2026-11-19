#!/usr/bin/env python3
"""Check added diff lines for credential literals without printing their values."""

import re
import sys
from pathlib import Path
from typing import Iterable, List, Pattern, Tuple

QUOTED_ASSIGNMENT = re.compile(
    r"""(?P<key>[A-Za-z_][\w-]*)["']?\s*[:=]\s*(?P<quote>["'])"""
    r"""(?P<value>.*?)(?P=quote)"""
)
BARE_ASSIGNMENT = re.compile(
    r"""(?P<key>[A-Za-z_][\w-]*)["']?\s*[:=]\s*(?P<value>[^\s"'`,;<]+)"""
)
XML_VALUE = re.compile(
    r"<(?P<key>[A-Za-z_][\w-]*)>" r"""(?P<value>[^<>\r\n"']{8,})</(?P=key)>"""
)
SECRET_KEY = re.compile(
    r"(?:^|[_-])(?:password|passwd|secret|token|api[_-]?key|"
    r"access[_-]?key|private[_-]?key|auth[_-]?token)(?:$|[_-])|"
    r"(?:password|passwd|secret|token|apikey|accesskey|privatekey|authtoken)$",
    re.IGNORECASE,
)
KNOWN_SECRET = re.compile(
    r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|"
    r"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
    r"AIza[\w-]{30,}|AKIA[A-Z0-9]{16}|tskey-[\w-]{15,}|AGE-SECRET-KEY-[\w]+)"
)
BEARER = re.compile(
    r"""authorization["']?\s*[:=]\s*["']?Bearer\s+(?P<value>[^\s"',;]+)""",
    re.IGNORECASE,
)
REFERENCE = re.compile(r"\$\{|\$\(|^\$[A-Za-z_]|^\{(?:env|file):|^var\.")
PLACEHOLDER = re.compile(
    r"^(?:your[_-]|change[_-]?me|replace[_-]?me|placeholder|<)|example\.(?:com|org|net)",
    re.IGNORECASE,
)
Finding = Tuple[str, int, str]


def is_literal(value: str, quoted: bool = True) -> bool:
    """Return whether a value resembles a credential rather than a reference."""
    return (
        len(value) >= 8
        and (quoted or not re.search(r"[()[\]\\]", value))
        and not REFERENCE.search(value)
        and not PLACEHOLDER.search(value)
    )


def scan_diff(lines: Iterable[str], allowlist: List[Pattern[str]]) -> List[Finding]:
    """Return file, new-file line and field names for added credential literals."""
    findings = []
    filename = "<diff>"
    line_number = 0
    for line in lines:
        if line.startswith("+++ "):
            filename = line[4:].strip().removeprefix("b/")
        elif line.startswith("@@ "):
            hunk = re.search(r"\+(\d+)", line)
            if hunk:
                line_number = int(hunk.group(1))
        elif line.startswith("+"):
            content = line[1:].rstrip("\n")
            fields = set()
            if not any(pattern.search(content) for pattern in allowlist):
                for pattern in (QUOTED_ASSIGNMENT, BARE_ASSIGNMENT, XML_VALUE):
                    for match in pattern.finditer(content):
                        key = match["key"]
                        quoted = pattern is not BARE_ASSIGNMENT
                        if SECRET_KEY.search(key) and is_literal(
                            match["value"], quoted
                        ):
                            fields.add(key)
                bearer = BEARER.search(content)
                if bearer and is_literal(bearer["value"]):
                    fields.add("Authorization")
                if KNOWN_SECRET.search(content):
                    fields.add("credential")
            findings.extend((filename, line_number, field) for field in sorted(fields))
            line_number += 1
        elif line.startswith(" "):
            line_number += 1
    return findings


def main() -> int:
    """Scan stdin and fail closed on findings or invalid allowlist configuration."""
    try:
        allowlist_path = Path(sys.argv[1])
        allowlist = (
            [
                re.compile(line)
                for line in allowlist_path.read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#")
            ]
            if allowlist_path.exists()
            else []
        )
        findings = scan_diff(
            (line.decode("utf-8", errors="replace") for line in sys.stdin.buffer),
            allowlist,
        )
    except (OSError, re.error) as error:
        print(f"Secret scan could not complete: {error}", file=sys.stderr)
        return 2
    for filename, line_number, field in findings:
        print(f"{filename}:{line_number}: potential {field} (value redacted)")
    if findings:
        print("Secret scan failed. Remove literals or review a narrow allowlist entry.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

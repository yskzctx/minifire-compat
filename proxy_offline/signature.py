"""Candidate login signing adapter; original-request verification is mandatory.

SHA1(body || material || UTF8(unique)) is a hypothesis from static analysis.
No live game request has yet validated it. Callers must pass through unchanged
when this function returns None. This code does not decrypt TLS.
"""
import hashlib
import hmac
import re


def resign_if_verified(original_body: bytes, rewritten_body: bytes, unique: str,
                       material: bytes, observed_signature: str) -> str | None:
    if not material or len(material) > 256 or len(unique.encode('utf-8')) > 256:
        return None
    if not re.fullmatch(r'[0-9A-Fa-f]{40}', observed_signature):
        return None
    suffix = material + unique.encode('utf-8')
    original_digest = hashlib.sha1(original_body + suffix).hexdigest()
    if not hmac.compare_digest(original_digest, observed_signature.lower()):
        return None
    result = hashlib.sha1(rewritten_body + suffix).hexdigest()
    return result.upper() if observed_signature == observed_signature.upper() else result

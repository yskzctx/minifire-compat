from proxy_offline.signature import resign_if_verified

SHA1_ABC = 'A9993E364706816ABA3E25717850C26C9CD0D89D'

def test_original_signature_is_required_before_any_rewrite():
    assert resign_if_verified(b'a', b'a', 'c', b'b', SHA1_ABC) == SHA1_ABC
    assert resign_if_verified(b'a', b'a', 'c', b'b', SHA1_ABC.lower()) == SHA1_ABC.lower()
    assert resign_if_verified(b'a', b'changed', 'c', b'b', '0'*40) is None
    assert resign_if_verified(b'a', b'changed', 'wrong', b'b', SHA1_ABC) is None

def test_invalid_or_ambiguous_signatures_are_never_accepted():
    for value in ('', 'x'*40, SHA1_ABC+'\n', SHA1_ABC[:39]):
        assert resign_if_verified(b'a', b'a', 'c', b'b', value) is None
    assert resign_if_verified(b'a', b'a', 'c', b'', SHA1_ABC) is None

def test_changed_body_gets_a_different_verified_signature():
    result = resign_if_verified(b'a', b'changed', 'c', b'b', SHA1_ABC)
    assert result is not None and len(result) == 40 and result != SHA1_ABC

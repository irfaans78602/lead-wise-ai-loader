from loader.uuid_gen import derive, NAMESPACE


def test_same_input_same_output():
    a = derive("client", "leadwise-platform")
    b = derive("client", "leadwise-platform")
    assert a == b


def test_different_kind_different_uuid():
    a = derive("client", "x")
    b = derive("ad", "x")
    assert a != b


def test_different_key_different_uuid():
    a = derive("client", "a")
    b = derive("client", "b")
    assert a != b


def test_multi_part_key():
    a = derive("faq", "ad-uuid", "30", "2026-01-15")
    b = derive("faq", "ad-uuid", "30", "2026-01-16")
    assert a != b


def test_namespace_is_fixed():
    expected = "7f3b1a4c-9d2e-4e8a-b1c5-8f6d0e3a7c9b"
    assert str(NAMESPACE) == expected
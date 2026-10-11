import pytest
from loader.uuid_gen import NAMESPACE


@pytest.fixture
def namespace():
    return NAMESPACE
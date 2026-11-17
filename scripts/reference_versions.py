"""Version policy for the hash-locked independent test tooling."""
from importlib.metadata import version
from pathlib import Path
import re

REQUIREMENTS = Path(__file__).with_name('reference-requirements.txt')


def expected_versions(requirements=REQUIREMENTS):
    pins = {}
    for line in requirements.read_text().splitlines():
        match = re.fullmatch(r'([a-zA-Z0-9_-]+)==([^\s]+)\s*(?:\\)?', line)
        if match:
            pins[match[1]] = match[2]
    if set(pins) != {'numpy', 'safetensors'}:
        raise ValueError('reference requirements must pin numpy and safetensors exactly')
    return pins


def assert_reference_versions():
    expected = expected_versions()
    actual = {name: version(name) for name in expected}
    for name in expected:
        assert actual[name] == expected[name], (
            f'{name}: installed {actual[name]}, locked {expected[name]}')
    return actual

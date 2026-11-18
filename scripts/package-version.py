#!/usr/bin/env python3
"""Read the package version declared by Dune."""
from pathlib import Path
import re

project = Path(__file__).resolve().parents[1] / 'dune-project'
versions = re.findall(r'^\(version ([^()\s]+)\)$', project.read_text(), re.MULTILINE)
if len(versions) != 1:
    raise SystemExit('dune-project must declare exactly one version')
print(versions[0])

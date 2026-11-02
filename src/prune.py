# SPDX-License-Identifier: MIT
import shutil
from pathlib import Path
for state in (Path.home() / 'snap').glob('*/common/snap-impurifier/*'):
    descriptor = state / 'implementation'
    if descriptor.is_file() and not Path(descriptor.read_text()).exists():
        shutil.rmtree(state)

# SPDX-License-Identifier: MIT
import argparse
import http.client
import json
import os
import pwd
import re
import socket
import subprocess
import tempfile
from pathlib import Path

class SnapConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect('/run/snapd.socket')

parser = argparse.ArgumentParser()
parser.add_argument('--owner')
parser.add_argument('snap')
args = parser.parse_args()
if not re.fullmatch(r'[a-z][a-z0-9-]{0,39}', args.snap):
    parser.error('invalid snap name')
connection = SnapConnection('localhost')
connection.request('GET', '/v2/snaps/' + args.snap)
response = connection.getresponse()
data = json.load(response)
if response.status != 200:
    parser.error(str(data))
revision = str(data['result']['revision'])
if not re.fullmatch(r'x?[0-9]+', revision):
    parser.error('unsupported native revision')
implementation = Path('/snap') / args.snap / revision
if args.owner:
    if os.geteuid() != 0:
        parser.error('--owner requires root')
    owner = pwd.getpwnam(args.owner)
    def drop():
        os.initgroups(owner.pw_name, owner.pw_gid)
        os.setgid(owner.pw_gid)
        os.setuid(owner.pw_uid)
else:
    drop = None
with tempfile.TemporaryDirectory(prefix='snap-impurifier-') as staging:
    for index, name in enumerate(['sdk-root', 'nix-root']):
        link = implementation / name
        target = os.readlink(link)
        command = ['nix-store', '--realise', target, '--add-root', f'{staging}/{index}', '--indirect']
        cache = implementation / ('sdk-cache' if name == 'sdk-root' else 'cache')
        if cache.is_dir():
            command += ['--option', 'substituters', cache.as_uri()]
            if os.geteuid() == 0:
                command += ['--option', 'require-sigs', 'false']
        subprocess.run(command, check=True)
        subprocess.run(['impurifier-register-root', str(link)], check=True, preexec_fn=drop)

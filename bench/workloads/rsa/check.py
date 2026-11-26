from hashlib import sha256
import json
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent
fixture_dir = root / 'fixtures'
manifest = json.loads((fixture_dir / 'manifest.json').read_text())
checks = 0
with TemporaryDirectory() as temp:
    out = Path(temp) / 'output.bin'
    for bits in (2048, 2080, 3072, 4096):
        fixture = fixture_dir / f'rsa-{bits}.bin'
        data = fixture.read_bytes()
        width, message_len, exponent_len = struct.unpack_from('<III', data)
        message_offset = 12 + 4 * width + exponent_len
        message = data[message_offset:message_offset + message_len]
        assert width * 8 == bits and len(message) == 48
        assert message == bytes((37*i + 11) & 255 for i in range(48))
        for offset in (0, 1, 7):
            for operation, expected in (
                ('rsa-pss-verify', b'\x01'),
                ('rsa-oaep-decrypt', message),
                ('rsa-oaep-decrypt-d-only', message),
            ):
                result = subprocess.check_output(
                    [root / 'openssl-rsa', operation, fixture, out, '2', str(offset)],
                    text=True,
                )
                wall, cpu, frequency = map(int, result.split())
                assert frequency == 1000000000 and wall > 0 and cpu > 0
                output = out.read_bytes()
                assert output == expected, (bits, offset, operation)
                checks += 1
        print(f'{bits} bits, 9 exact execution checks, fixture SHA256 {sha256(data).hexdigest()}')
print(f'{checks} checks passed')

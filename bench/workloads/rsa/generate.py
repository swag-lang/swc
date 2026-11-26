import hashlib
import json
from pathlib import Path
import struct

import cryptography
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

root = Path(__file__).resolve().parent
out = root / "fixtures"
out.mkdir(exist_ok=True)
pss = padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=32)
oaep = padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=b"")
keys = []
for bits in (2048, 2080, 3072, 4096):
    width = bits // 8
    half = width // 2
    private = rsa.generate_private_key(public_exponent=65537, key_size=bits)
    public = private.public_key()
    numbers = private.private_numbers()
    modulus = numbers.public_numbers.n
    exponent = numbers.public_numbers.e
    exponent_bytes = exponent.to_bytes((exponent.bit_length() + 7) // 8, "big")
    message = bytes((37 * index + 11) & 255 for index in range(48))
    signature = private.sign(message, pss, hashes.SHA256())
    ciphertext = public.encrypt(message, oaep)
    public.verify(signature, message, pss, hashes.SHA256())
    assert private.decrypt(ciphertext, oaep) == message
    assert modulus.bit_length() == bits and numbers.p * numbers.q == modulus
    assert numbers.dmp1 == numbers.d % (numbers.p - 1)
    assert numbers.dmq1 == numbers.d % (numbers.q - 1)
    assert (numbers.q * numbers.iqmp) % numbers.p == 1
    assert len(signature) == len(ciphertext) == width

    payload = b"".join((
        struct.pack("<III", width, len(message), len(exponent_bytes)),
        modulus.to_bytes(width, "big"),
        numbers.d.to_bytes(width, "big"),
        exponent_bytes,
        signature,
        ciphertext,
        message,
        *(value.to_bytes(half, "big") for value in (
            numbers.p, numbers.q, numbers.dmp1, numbers.dmq1, numbers.iqmp
        )),
    ))
    filename = f"rsa-{bits}.bin"
    (out / filename).write_bytes(payload)
    keys.append({
        "bits": bits,
        "width": width,
        "message_bytes": len(message),
        "public_exponent": exponent,
        "file": filename,
        "file_bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "message_hex": message.hex(),
        "signature_sha256": hashlib.sha256(signature).hexdigest(),
        "ciphertext_sha256": hashlib.sha256(ciphertext).hexdigest(),
    })

(out / "manifest.json").write_text(json.dumps({
    "generator": f"Python cryptography {cryptography.__version__}",
    "pss": "SHA-256, MGF1-SHA-256, 32-byte salt",
    "oaep": "SHA-256, MGF1-SHA-256, empty label",
    "fixtures": keys,
}, indent=2) + "\n")

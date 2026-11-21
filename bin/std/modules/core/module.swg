/*
Core is the foundation library shared by Swag applications and standard modules.
It provides owned collections and strings, text and Unicode processing, files and
paths, serialization, mathematics, hashing, cryptography, time, concurrency, reflection,
diagnostics, input, and access to the host environment.

The APIs are grouped into focused namespaces such as [[Core.Math]], [[Core.File]],
[[Core.Path]], [[Core.Time]], [[Core.Threading]], [[Core.Sync]],
[[Core.Serialization]], [[Core.Globalization]], [[Core.Scc]], [[Core.Crypto]], and
[[Core.Reflection]]. Frequently used value types, including [[Core.Array]], [[Core.HashTable]],
[[Core.OrderedMap]], [[Core.OrderedSet]],
[[Core.Deque]], [[Core.PriorityQueue]], and [[Core.String]], live directly in `Core`.

## Read and process a file

```swag
using Core

let text = try File.readAllText("settings.txt")

var lines: Array'String
for line in Tokenize.splitLines(text.toString()) do
    lines.add(line)
```

Owned containers release their storage automatically. Slices and string views
borrow storage instead; keep their source alive and do not retain them across an
operation that can reallocate that source.

## Derive short-lived key material

```swag
using Core

let password = cast(const [..] u8) "password"
let salt     = cast(const [..] u8) "application salt"
var key: [32] u8
defer Crypto.secureClear(key)

try Crypto.pbkdf2HmacSha256(password, salt, 200_000, key)
```

Cryptographic randomness and guaranteed clearing use the target operating
system behind the portable [[Core.Crypto]] API.

## Expand existing key material

[[Core.Crypto.hkdfSha256]] derives independent keys from input key material and context:

```swag
using Core

let salt             = cast(const [..] u8, "session salt")
let inputKeyMaterial = cast(const [..] u8, "already secret key material")
let info             = cast(const [..] u8, "file encryption key")
var key: [32] u8
defer Crypto.secureClear(key)

try Crypto.hkdfSha256(salt, inputKeyMaterial, info, key)
```

## Agree on a shared key

Use [[Core.Crypto.x25519PublicKey]] to publish an X25519 public key and
[[Core.Crypto.x25519SharedSecret]] to derive the same secret on both peers. Fill private keys
with [[Core.Crypto.randomBytes]] and clear them after use. Shared-secret derivation rejects
low-order peer keys.

```swag
using Core

var privateKey: [Crypto.X25519KeySize] u8
var sharedKey:  [Crypto.X25519KeySize] u8
defer Crypto.secureClear(privateKey)
defer Crypto.secureClear(sharedKey)

try Crypto.randomBytes(privateKey)
try Crypto.x25519SharedSecret(privateKey, peerPublicKey, sharedKey)
```

## Sign messages

[[Core.Crypto.ed25519PublicKey]], [[Core.Crypto.ed25519Sign]], and
[[Core.Crypto.ed25519Verify]] implement Ed25519 with 32-byte seeds and public keys and 64-byte
signatures. Verification returns `false` for invalid signatures and rejects noncanonical points.

```swag
using Core

var seed: [Crypto.Ed25519KeySize] u8
var publicKey: [Crypto.Ed25519KeySize] u8
var signature: [Crypto.Ed25519SignatureSize] u8
defer Crypto.secureClear(seed)
defer Crypto.secureClear(publicKey)
defer Crypto.secureClear(signature)

try Crypto.randomBytes(seed)
try Crypto.ed25519PublicKey(seed, publicKey)
try Crypto.ed25519Sign(seed, "message", signature)
Swag.assert(try Crypto.ed25519Verify(publicKey, "message", signature), "signature verification failed")
```

## Encrypt authenticated data

[[Core.Crypto.aesGcmEncrypt]] and [[Core.Crypto.aesGcmDecrypt]] provide AES-GCM with 12-byte
nonces and complete 16-byte tags. Never reuse a nonce with the same key. Decryption leaves the
destination untouched if authentication fails.

[[Core.Crypto.xchacha20Poly1305Seal]] and [[Core.Crypto.xchacha20Poly1305Open]] provide the
XChaCha20-Poly1305 AEAD with 24-byte nonces. Its larger nonce lowers accidental collision risk;
nonce reuse with one key is still unsafe.

## Interoperate with RSA peers

[[Core.Crypto.rsaOaepSha256Encrypt]] and [[Core.Crypto.rsaOaepSha256Decrypt]] use RSAES-OAEP
with SHA-256. [[Core.Crypto.rsaPssSha256Sign]] and [[Core.Crypto.rsaPssSha256Verify]] use
RSASSA-PSS with SHA-256 and a 32-byte salt. Pass modulus and exponent components as unsigned
big-endian byte slices from 2048- through 4096-bit keys. These APIs do not parse PEM or DER key
containers. PKCS#1 v1.5 padding is not provided.

```swag
using Core

var key: [16] u8
var nonce: [Crypto.AesGcmNonceSize] u8
var associatedData: [4] u8
var plaintext: [16] u8
var ciphertext: [16] u8
var plaintextOutput: [16] u8
var tag: [Crypto.AesGcmTagSize] u8
defer Crypto.secureClear(key)
defer Crypto.secureClear(nonce)
defer Crypto.secureClear(plaintext)
defer Crypto.secureClear(ciphertext)
defer Crypto.secureClear(plaintextOutput)
defer Crypto.secureClear(tag)

try Crypto.randomBytes(key)
try Crypto.randomBytes(nonce)
try Crypto.randomBytes(plaintext)
try Crypto.aesGcmEncrypt(key, nonce, associatedData, plaintext, ciphertext, tag)
try Crypto.aesGcmDecrypt(key, nonce, associatedData, ciphertext, tag, plaintextOutput)
```

## Hash files and derive context-bound keys

[[Core.Hash.Blake3]] provides unkeyed hashing, keyed hashing, context-derived keys,
and extendable output. Large one-shot inputs use parallel chunk processing.

## Store independently readable payloads

[[Core.Scc]] writes a versioned Swag Chunk Container whose manifest remains cheap to read.
Each payload has a stable type, role, codec, checksum, and file range, so an application can
load a thumbnail or metadata chunk without reading the main document.

```swag
using Core

let profile = try Guid128.parse("fc9456cf-5ec9-4710-bd12-b6bdd64a77a5")
let role    = try Guid128.parse("582e4036-ee6f-45b5-86d9-7972bb7e0a19")

var writer: Scc.Writer
writer.initialize(profile)
let previewId = try writer.addChunk("preview bytes", {roleId: role})
try writer.saveAtomic("capture.scc")

var reader: Scc.Reader
try reader.initialize("capture.scc")
let preview = try reader.readChunk(previewId)
```
*/
#static if #os == Swag.TargetOs.Windows
{
    #import("win32")
}

#static if #os == Swag.TargetOs.Linux
{
    #import("linux")
}

#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Core"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/core"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.core"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.titleContent = "Swag Std.Core"
    cfg.genDoc.css          = "css/style.css"
}

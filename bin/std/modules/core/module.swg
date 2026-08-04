/*
Core is the foundation library shared by Swag applications and standard modules.
It provides owned collections and strings, text and Unicode processing, files and
paths, serialization, mathematics, hashing, cryptography, time, concurrency, reflection,
diagnostics, input, and access to the host environment.

The APIs are grouped into focused namespaces such as [[Core.Math]], [[Core.File]],
[[Core.Path]], [[Core.Time]], [[Core.Threading]], [[Core.Sync]],
[[Core.Serialization]], [[Core.Crypto]], and [[Core.Reflection]]. Frequently used value types,
including [[Core.Array]], [[Core.HashTable]], and [[Core.String]], live directly
in `Core`.

## Read and process a file

```swag
using Core

let text = try File.readAllText("settings.txt")

var lines: Array'String
for line in text.splitLines() do
    lines.add(line)
```

Owned containers release their storage automatically. Slices and string views
borrow storage instead; keep their source alive and do not retain them across an
operation that can reallocate that source.

## Derive short-lived key material

```swag
using Core

let password = @mkslice(cast(const [*] u8) @dataof("password"), 8)
let salt     = @mkslice(cast(const [*] u8) @dataof("application salt"), 16)
var key: [32] u8

try Crypto.pbkdf2HmacSha256(password, salt, 200_000, key)
defer Crypto.secureClear(key)
```

Cryptographic randomness and guaranteed clearing use the target operating
system behind the portable [[Core.Crypto]] API.

On Windows, [[Core.File.availableDriveLetters]] reports letters that are safe
to offer for a new logical-drive mount point.
*/
#static if #os == Swag.TargetOs.Windows
{
    #import("win32")
    #import("xinput")
}

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
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

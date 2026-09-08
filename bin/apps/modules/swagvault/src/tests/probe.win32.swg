#global if WINDOWS and #hastag("vault.mount-probe")

using Core

func probeReadOnlyMount() fail
{
    let path = Env.variable("SWAG_VAULT_PROBE_PATH")
    var password = Env.variable("SWAG_VAULT_PROBE_PASSWORD")
    defer Core.Crypto.secureClear(password.toSlice())
    let destination = try Integration.findFreeMountPoint()
    var mounted: WinFsp.MountedVolume
    try mounted.open(path, password.toSlice(), destination, readOnly: true)
    Console.println("PROBE: read-only mount succeeded on ", destination)
    let entries = try Directory.enumerate(Integration.driveRoot(destination), {})
    Console.println("PROBE: root enumeration succeeded, entries: ", entries.count)
    try mounted.close()
    Console.println("PROBE: unmount succeeded")
}

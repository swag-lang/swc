using Core

// One destination a host filesystem backend can currently mount on.
//
// `id` is the stable value persisted by Swag Vault and passed back to the backend. `label` is the
// host-facing name shown in the interface; another host may therefore expose a path or another
// native mount identity without teaching the application how that identity is formed.
struct MountDestination
{
    id:    String
    label: String
}

// Capacity currently exposed by one live mount.
struct MountedVaultSpace
{
    total:     u64
    available: u64
}

// One live host filesystem mount.
//
// The backend owns the object behind `handle`. Keeping that representation opaque lets the
// application own mount orchestration without retaining a WinFsp type in its portable state.
#[Swag.NoCopy]
struct MountedVault
{
    handle: *void?
}

impl MountedVault
{
    // Opens the container at `path` with `password` and exposes it on `destination`.
    //
    // `readOnly` mounts a drive nothing can change. A non-empty `protectionPassword` authenticates
    // the hidden volume, so writes into its region are refused for as long as this mount lives.
    mtd open(path: string, password: const [..] u8, destination: string, readOnly = false, protectionPassword: const [..] u8 = "") fail
    {
        Swag.assert(.handle == null)
        .handle = try mountVaultNative(path, password, destination, readOnly, protectionPassword)
    }

    // Unmounts the drive and releases the backend object. Closing a closed mount does nothing.
    //
    // The handle is released even when the final synchronization fails, which is what the
    // failure then reports.
    mtd close() fail
    {
        if not .handle do
            return

        let handle = .handle
        .handle = null
        try unmountVaultNative(handle)
    }

    // Returns the capacity the live mount currently exposes.
    mtd space()->MountedVaultSpace
    {
        Swag.assert(.handle != null)
        return mountedVaultSpaceNative(.handle)
    }

    mtd opDrop() { discard catch .close() }
}

// Returns the destinations the active host backend can currently mount on.
func availableMountDestinations()->Array'MountDestination => availableMountDestinationsNative()

// Returns whether this process invocation belongs to the host filesystem helper.
func isMountHostInvocation()->bool => isMountHostInvocationNative()

// Runs the host filesystem helper and returns its process exit code.
func runMountHost()->s32 => runMountHostNative()

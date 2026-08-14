using Core

// One destination a host filesystem backend can currently mount on.
//
// `id` is the stable value persisted by sCrypt and passed back to the backend. `label` is the
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
    handle: #null *void
}

impl MountedVault
{
    mtd open(path: string, password: const [..] u8, destination: string, readOnly = false) fail
    {
        Debug.assert(.handle == null)
        .handle = mountVaultNative(path, password, destination, readOnly)
    }

    mtd close() fail
    {
        if !.handle do
            return

        let handle = .handle!
        .handle = null
        unmountVaultNative(handle)
    }

    mtd space()->MountedVaultSpace
    {
        Debug.assert(.handle != null)
        return mountedVaultSpaceNative(.handle!)
    }

    mtd opDrop() { discard catch .close() }
}

// Returns the destinations the active host backend can currently mount on.
func availableMountDestinations()->Array'MountDestination
{
    return availableMountDestinationsNative()
}

// Whether this process invocation belongs to the host filesystem helper.
func isMountHostInvocation()->bool => isMountHostInvocationNative()

// Runs the host filesystem helper and returns its process exit code.
func runMountHost()->s32 => runMountHostNative()

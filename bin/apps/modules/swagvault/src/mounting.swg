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
    handle:  *void?
    privacy: File.MountPrivacyPublisher
    mutex:   Swag.Mutex
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
        var root = String.from(destination)
        if WINDOWS and root.count == 2 and root[1] == ':' do
            root += '/'
        catch .privacy.open(root)
        {
            let error = Swag.err
            discard catch .close(force: true)
            fail error
        }
    }

    // Unmounts the drive and releases the backend object. Closing a closed mount does nothing.
    //
    // An ordinary close refuses an occupied mount and retains ownership. A forced close
    // invalidates outstanding handles. After detachment, even a commit failure releases the
    // backend; callers inspect handle to distinguish that result from a retained mount.
    mtd close(force = false) fail
    {
        .mutex.lock()
        defer .mutex.unlock()
        if not .handle do
            return

        defer if not .handle do
            .privacy.close()
        try unmountVaultNative(&.handle, force)
    }

    // Publishes the current UI policy without changing the mount or its open files.
    mtd setPrivateMode(privateMode: bool)
    {
        .mutex.lock()
        defer .mutex.unlock()
        .privacy.setPrivateMode(privateMode)
    }

    // Returns the capacity the live mount currently exposes.
    mtd space()->MountedVaultSpace
    {
        .mutex.lock()
        defer .mutex.unlock()
        if not .handle do
            return {}
        return mountedVaultSpaceNative(.handle)
    }

    mtd opDrop() { discard catch .close(force: true) }
}

// Returns the destinations the active host backend can currently mount on.
func availableMountDestinations()->Array'MountDestination => availableMountDestinationsNative()

// Returns whether this process invocation belongs to the host filesystem helper.
func isMountHostInvocation()->bool => isMountHostInvocationNative()

// Runs the host filesystem helper and returns its process exit code.
func runMountHost()->s32 => runMountHostNative()

// Whether an ordinary unmount was refused because the drive still has open handles.
func isBusyError(err: any?)->bool
{
    if err is Error as error do
        return error.kind == .Busy
    return false
}

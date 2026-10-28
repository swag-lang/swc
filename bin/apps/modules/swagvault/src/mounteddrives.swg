using Core, Gui

// One drive Swag Vault currently exposes, and the container behind it.
struct MountedDrive
{
    volume:         *MountedVault?     // Live mount, owned by this entry until it is unmounted.
    path:           String             // Container file the drive reads and writes.
    drive:          String             // Stable backend destination identifier persisted by Swag Vault.
    mountLabel:     String             // Host-facing destination name shown on the vault's row.
    needsPassword:  bool               // Whether a password was needed to open the container.
    readOnly:       bool               // Whether the drive was mounted for reading alone.
    atStartup:      bool               // Whether Swag Vault mounts this container again the next time it starts.
    totalBytes:     u64                // Capacity exposed by the mounted filesystem.
    availableBytes: u64                // Free capacity observed when the entry was last refreshed.
    protectHidden:  bool               // Hidden access must be requested again on a writable startup mount.
}

// The drives Swag Vault currently exposes, in the order they came up.
//
// The list of vaults shows each of them on the row of its container; this is what Windows sees,
// and what the window must close on its way out. Entries are never sorted, which is what lets an
// index stand for a drive while the window works on it.
struct MountedDrives
{
    drives: Array'MountedDrive
}

impl MountedDrives
{
    // Returns the drive exposing the container at `path`, or null when that vault is locked.
    mtd find(path: string)->*MountedDrive?
    {
        for &one in .drives where one.path == path do
            return one
        return null
    }

    // Returns the index of the drive exposing the container at `path`, or `Swag.U64.Max`.
    mtd indexOf(path: string)->u64
    {
        for &one, index in .drives where one.path == path do
            return index
        return Swag.U64.Max
    }

    // Reads again what each live mount holds and has free.
    mtd refreshSpace()
    {
        for &one in .drives where one.volume
        {
            let space = one.volume.space()
            one.totalBytes     = space.total
            one.availableBytes = space.available
        }
    }

    // Hands over the mount at `index` and drops its entry.
    //
    // The caller becomes responsible for closing and releasing what it gets back: this model
    // holds a mount only while it shows it.
    mtd detach(index: u64)->*MountedVault?
    {
        Swag.assert(index < .drives.count)
        let result = .drives[index].volume
        .drives.removeAtOrdered(index)
        return result
    }
}

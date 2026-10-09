using Core

// What went wrong, in the terms the caller above the volume can act on.
//
// The layer reports a kind and a diagnostic sentence; whoever presents the failure decides
// the wording. The filesystem bridge turns a kind into an NTSTATUS
// ([[WinFsp.statusFromError]]) and the application window turns it into a localized
// sentence, so a kind exists when one of those two has to tell it apart.
enum ErrorKind
{
    HiddenProtected       // A hidden region stopped writes or prevents changing geometry.
    General               // Nothing more precise is known.
    InvalidInput          // The operation was asked for something it cannot do.
    PasswordRequired      // The operation needs a password and got none.
    SizeTooSmall          // The requested capacity is below the smallest container.
    PasswordOrDamaged     // The container did not open. See the note below.
    NotFound              // The named entry, or a password slot, does not exist.
    AlreadyExists         // The name is taken.
    AccessDenied          // The entry exists and refuses the operation.
    WriteProtected        // The container is open read only and refuses every change.
    SparseContainer       // Sparse files reveal allocation and are never accepted as containers.
    NotDirectory          // A directory was needed, and the entry is a file.
    IsDirectory           // A file was needed, and the entry is a directory.
    DirectoryNotEmpty     // The directory still holds entries.
    DiskFull              // No room is left: for blocks, for metadata, or for key slots.
    Corrupted             // An open container no longer reads back what it stored.
    Io                    // The underlying file could not be read or written.
    Elevated              // The application runs as administrator, so Windows Explorer cannot see its drives.
    DriverUnavailable     // The virtual drive component could not be loaded, started, or reached.
    Canceled              // The caller stopped the operation.
}

// One failure raised by the volume layer: what kind of failure it is, the native status that came
// with it, and where it was raised.
//
// It holds no sentence. The shell says the sentence for [[ErrorKind]] in the active language,
// shows `code` under it when there is one, and sends `location` to the debugger output for
// whoever reads a report.
struct Error
{
    using base: Swag.BaseError
    kind:       ErrorKind
    code:       u64     // A native status (NTSTATUS or HRESULT), or 0.
    location:   Swag.SourceCodeLocation     // Where the volume layer raised it.
}

// The error a volume operation fails with. Raise it with `fail volumeError(...)`, so the guard it
// ends is visibly a way out.
//
// > NOTE:
// > Every way a container can refuse to open reports [[ErrorKind.PasswordOrDamaged]] —
// > a wrong password, a damaged container, and an older format version are deliberately
// > indistinguishable, and nothing the error carries may tell them apart either.
func volumeError(kind = ErrorKind.General, code = 0'u64, location = #callerlocation)->Error => {kind: kind, code: code, location: location}

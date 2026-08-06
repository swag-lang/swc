using Core

// What went wrong, in the terms the caller above the volume can act on.
//
// The layer reports a kind and a diagnostic sentence; whoever presents the failure decides
// the wording. The filesystem bridge turns a kind into an NTSTATUS
// ([[WinFsp.statusFromError]]) and the application window turns it into a localized
// sentence, so a kind exists when one of those two has to tell it apart.
enum ErrorKind
{
    General               // Nothing more precise is known.
    InvalidInput          // The operation was asked for something it cannot do.
    PasswordRequired      // The operation needs a password and got none.
    SizeTooSmall          // The requested capacity is below the smallest container.
    PasswordOrDamaged     // The container did not open. See the note below.
    NotFound              // The named entry, or a password slot, does not exist.
    AlreadyExists         // The name is taken.
    AccessDenied          // The entry exists and refuses the operation.
    NotDirectory          // A directory was needed, and the entry is a file.
    IsDirectory           // A file was needed, and the entry is a directory.
    DirectoryNotEmpty     // The directory still holds entries.
    DiskFull              // No room is left: for blocks, for metadata, or for key slots.
    Corrupted             // An open container no longer reads back what it stored.
    Io                    // The underlying file could not be read or written.
    Canceled              // The caller stopped the operation.
}

// One failure raised by the volume layer.
//
// `message` is the diagnostic sentence, in English, for whoever reads a report. It is not
// what a reader of the application sees: the shell says the sentence for [[ErrorKind]] in
// the active language and keeps this one behind it.
struct Error
{
    using base: Swag.BaseError
    kind:       ErrorKind
}

// Reports a failure with its diagnostic sentence and the kind the caller acts on.
//
// > NOTE:
// > Every way a container can refuse to open reports [[ErrorKind.PasswordOrDamaged]] —
// > a wrong password, a damaged container, and an older format version are deliberately
// > indistinguishable, and `message` must not tell them apart either.
func failWith(message: string, kind = ErrorKind.General) fail
{
    fail Error{base: {Errors.mkString(message)}, kind: kind}
}

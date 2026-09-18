using Core

// Bytes handed to the volume layer after a password and its key files have been combined.
//
// The array owns key material and therefore clears its allocation before releasing it. Keeping
// that contract on a type rather than on every caller makes an early return as safe as success.
#[Swag.NoCopy]
struct VaultCredential
{
    bytes: Array'u8
}

impl VaultCredential
{
    // Wipes the key material and empties the credential.
    mtd clear()
    {
        Core.Crypto.secureClear(.bytes.toSlice())
        .bytes.clear()
    }

    mtd opDrop() { .clear() }

    // Returns a view of the key material, valid until the credential is cleared or dropped.
    mtd const toSlice()->const [..] u8 => .bytes.toSlice()
}

// Password and ordered key-file paths that together open a vault.
//
// Paths are deliberately transient. The UI owns the authoritative selection and an operation
// copies it here only for the lifetime of its worker. Password bytes are cleared on every exit.
#[Swag.NoCopy]
struct VaultAccess
{
    password: Array'u8
    keyFiles: Array'String
}

// Feeds `value` to the digest as eight little-endian bytes.
private func updateAccessWord(hash: *Core.Hash.Blake2b, value: u64)
{
    var bytes: [8] u8
    bytes[0] = cast(u8) value
    bytes[1] = cast(u8) (value >> 8)
    bytes[2] = cast(u8) (value >> 16)
    bytes[3] = cast(u8) (value >> 24)
    bytes[4] = cast(u8) (value >> 32)
    bytes[5] = cast(u8) (value >> 40)
    bytes[6] = cast(u8) (value >> 48)
    bytes[7] = cast(u8) (value >> 56)
    hash.update(bytes)
}

impl VaultAccess
{
    // Replaces this input with one snapshot of the controls the operation consumes.
    mtd setInputs(password: const [..] u8, keyFiles: const [..] String)
    {
        .clear()
        .password.add(password)
        for &path in keyFiles do
            .keyFiles.add(String.from(path.toString()))
    }

    // Wipes the password bytes and forgets the key-file paths.
    mtd clear()
    {
        Core.Crypto.secureClear(.password.toSlice())
        .password.clear()
        .keyFiles.clear()
    }

    mtd opDrop() { .clear() }

    // Returns whether this access needs anything at all: a password, a key file, or both.
    mtd const isProtected()->bool => not .password.isEmpty() or not .keyFiles.isEmpty()

    // Produces the byte string the key-slot format consumes.
    //
    // Without key files, the password bytes are used directly. With key files, a domain-separated
    // streaming digest binds the password, the ordered file count, every file length, and every
    // byte. Paths stay out of the digest, so moving an unchanged key file does not change what
    // opens the vault. Fails when a key file cannot be read in full.
    mtd const derive()->VaultCredential fail
    {
        var result: retval
        if .keyFiles.isEmpty()
        {
            result.bytes.add(.password.toSlice())
            return result
        }

        const Context = "swag vault access key files v1"
        var hash = try Core.Hash.Blake2b.create(Core.Hash.Blake2bMaxDigestSize)
        hash.update(Context)
        updateAccessWord(&hash, .password.count)
        hash.update(.password.toSlice())
        updateAccessWord(&hash, .keyFiles.count)

        var buffer: [64 * 1024] u8
        defer Core.Crypto.secureClear(buffer)
        for &path in .keyFiles
        {
            var stream = try File.openRead(path.toString())
            let size   = try stream.size()
            updateAccessWord(&hash, size)

            var remaining = size
            while remaining
            {
                let wanted = Math.min(remaining, #sizeof(buffer))
                let count  = try stream.read(buffer[until wanted])
                if not count do
                    fail Swag.SystemError{"key file ended before its declared size"}
                hash.update(buffer[until count])
                remaining -= count
            }
        }

        result.bytes.resize(Core.Hash.Blake2bMaxDigestSize)
        try hash.finalize(result.bytes.toSlice())
        return result
    }
}

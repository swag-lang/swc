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
    mtd clear()
    {
        Core.Crypto.secureClear(.bytes.toSlice())
        .bytes.clear()
    }

    mtd opDrop()
    {
        .clear()
    }

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

    mtd clear()
    {
        Core.Crypto.secureClear(.password.toSlice())
        .password.clear()
        .keyFiles.clear()
    }

    mtd opDrop()
    {
        .clear()
    }

    mtd const isProtected()->bool => !.password.isEmpty() or !.keyFiles.isEmpty()

    // Produces the byte string the existing key-slot format consumes.
    //
    // Without key files, the password bytes are used directly. With key files, a
    // domain-separated streaming digest binds the
    // password, the ordered file count, every file length, and every byte. Paths stay out of the
    // digest, so moving an unchanged key file does not change what opens the vault.
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
                if !count do
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

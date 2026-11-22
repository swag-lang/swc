using Core

private const KeyFileChunkSize  = 1024'u64 * 1024
private const KeyFileBatchSize  = 8 * KeyFileChunkSize
private const KeyFileDigestSize = Core.Hash.Blake2bMaxDigestSize

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
    for i in 8 do
        bytes[i] = cast(u8, (value >> (i * 8)) & 0xFF)
    hash.update(bytes)
}

private func requireAccessRunning(progress: *VolumeProgress?) fail
{
    if progress and progress.isCanceled() do
        fail volumeError(.Canceled)
}

// Binds one file length and its ordered chunk digests to the access digest.
private func hashKeyFile(hash: *Core.Hash.Blake2b, path: string, progress: *VolumeProgress?) fail
{
    try requireAccessRunning(progress)
    var stream = try File.openRead(path)
    let size   = try stream.size()
    progress?.setTotal(size, .KeyFile)
    updateAccessWord(hash, size)

    var buffer: Array'u8
    buffer.resize(Math.min(size, KeyFileBatchSize))
    defer Core.Crypto.secureClear(buffer.toSlice())
    var digests: [KeyFileBatchSize / KeyFileChunkSize * KeyFileDigestSize] u8
    defer Core.Crypto.secureClear(digests)

    var done = 0'u64
    while done < size
    {
        try requireAccessRunning(progress)
        let length = Math.min(size - done, buffer.count)
        if not (try stream.readExact(buffer[until length])) do
            fail volumeError(.Io)

        let data  = buffer[until length]
        let count = (length + KeyFileChunkSize - 1) / KeyFileChunkSize
        try parallel for |data, &digests, progress| chunk in count
        {
            try requireAccessRunning(progress)
            let first = chunk * KeyFileChunkSize
            let end   = Math.min(first + KeyFileChunkSize, data.count)
            let slot  = chunk * KeyFileDigestSize
            try Core.Hash.Blake2b.compute(data[first until end], digests[slot until slot + KeyFileDigestSize])
        }

        hash.update(digests[until count * KeyFileDigestSize])
        done += length
        progress?.publish(done)
    }
}

impl VaultAccess
{
    // Replaces this input with one snapshot of the controls the operation consumes.
    mtd setInputs(password: const [..] u8, keyFiles: const [..] String)
    {
        .clear()
        .password.add(password)
        for &path in keyFiles do
            .keyFiles.add(path[])
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
    // digest binds the password, the ordered file count, every file length, and the chunk digests
    // of every file. Paths stay out of the digest, so moving an unchanged key file does not change what
    // opens the vault. Reports bytes processed for each key file and stops at a chunk boundary
    // when canceled. Fails when a key file cannot be read in full.
    mtd const derive(progress: *VolumeProgress? = null)->VaultCredential fail
    {
        try requireAccessRunning(progress)

        var result: #returntype
        if .keyFiles.isEmpty()
        {
            result.bytes.add(.password.toSlice())
            return result
        }

        const Context = "swag vault access key files v2"
        var hash = try Core.Hash.Blake2b.create(KeyFileDigestSize)
        hash.update(Context)
        updateAccessWord(&hash, .password.count)
        hash.update(.password.toSlice())
        updateAccessWord(&hash, .keyFiles.count)

        for &path in .keyFiles do
            try hashKeyFile(&hash, path.toString(), progress)
        try requireAccessRunning(progress)

        result.bytes.resize(KeyFileDigestSize)
        try hash.finalize(result.bytes.toSlice())
        return result
    }
}

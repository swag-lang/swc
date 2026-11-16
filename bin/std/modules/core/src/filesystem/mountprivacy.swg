#global public
#global namespace File

// A live mount's retention policy. An empty root has no published policy.
//
// Resolve this snapshot before retaining a path, then call `refresh` while it is in use.
// `activation` changes whenever privacy is enabled, including an on/off cycle between reads.
// A snapshot retains the last policy after a normal unmount. Unreadable state is private. Snapshots
// are process-local and must not be serialized. This is a retention hint, not access control.
struct MountPrivacy
{
    public readonly
    {
        root:        String     // Canonical publication root, or empty for an ordinary path.
        channel:     String     // Opaque live-publication identity; contains no source path.
        instance:    u64        // Random identity of this publication's lifetime.
        activation:  u64        // Monotonic private-activation counter within this instance.
        privateMode: bool       // Whether consumers must suppress persistent records.
    }

    internal reader: *MountPrivacyReader?
}

// Owns one process-local publication of a mount's retention policy in shared memory.
//
// No paths or credentials are stored in shared memory. Keep the publication for the mount's lifetime.
// Updates and close are serialized internally; opening and destroying require exclusive ownership.
#[Swag.Opaque, Swag.NoCopy]
struct MountPrivacyPublisher
{
    internal
    {
        channel: String
        handle:  const [*] void?
        data:    *MountPrivacyData?
        mutex:   Swag.Mutex
    }
}

internal struct MountPrivacyReader
{
    references: s32 = 1
    handle:     const [*] void?
    data:       *MountPrivacyData?
}

internal struct MountPrivacyData
{
    sequence:   u64
    instance:   u64
    activation: u64
    flags:      u64
}

internal func mountPrivacyChannel(root: string)->String
{
    var identity = String.from(root)
    while identity.count > 1 and Path.isDirectorySeparator(identity[identity.count - 1]) do
        identity.remove(identity.count - 1, 1)
    if WINDOWS do
        identity.makeLower(.Unicode)
    identity += 0'u8
    identity += Env.isSandboxed() ? "sandbox" : "host"
    if Env.isSandboxed()
    {
        identity += 0'u8
        identity += Env.sandboxRoot()
    }

    let digest = Hash.Sha256.compute(cast(const [..] u8, identity.toString()))
    var result = String.from("Swag.MountPrivacy.1.")
    for word in digest do
        result += Format.toString("%{X08}", word)
    return result
}

impl MountPrivacy
{
    // Follows filesystem aliases, then finds a publication on the path or one of its parents.
    //
    // Known Swag Vault filesystems without a readable publication are conservatively private.
    // A path that cannot be resolved and has no recognized mount returns an empty policy.
    func query(path: string)->MountPrivacy
    {
        var result: #returntype
        var candidate = mountPrivacyPathNative(path)
        if candidate.isEmpty() do
            return result
        let protectedRoot = mountPrivacyProtectedRootNative(candidate)
        for
        {
            result.channel = mountPrivacyChannel(candidate)
            if readMountPrivacyNative(result.channel, &result)
            {
                result.root = candidate
                return result
            }

            let parent = Path.directoryName(candidate)
            if not parent or Path.equals(parent, candidate) do
                break
            candidate = String.from(parent)
        }

        result = {}
        if not protectedRoot.isEmpty()
        {
            result.root        = protectedRoot
            result.channel     = mountPrivacyChannel(protectedRoot)
            result.privateMode = true
        }

        return result
    }

    // Refreshes without filesystem access. Returns whether the identity or policy changed.
    //
    // Retains the final state after unmount, preventing late saves from losing provenance.
    mtd refresh()->bool
    {
        if .root.isEmpty() do
            return false
        let previousInstance   = .instance
        let previousActivation = .activation
        let previousPrivate    = .privateMode
        let readable           = .reader ? readMountPrivacyData(unwrap .reader.data, me) : readMountPrivacyNative(.channel, me)
        if not readable do
            .privateMode = true
        return .instance != previousInstance or
               .activation != previousActivation or
               .privateMode != previousPrivate
    }

    // Shares the live read view, so copies retain terminal state without retaining source files.
    mtd opPostCopy()
    {
        if .reader do
            Atomic.add(&.reader.references, 1)
    }

    // Releases this snapshot's shared view.
    mtd opDrop()
    {
        if .reader and Atomic.add(&.reader.references, -1) == 1
        {
            closeMountPrivacyReaderNative(.reader)
            Memory.delete(.reader)
        }

        .reader = null
    }
}

impl MountPrivacyPublisher
{
    // Publishes `privateMode` for an existing mount root. Fails if its channel is already owned.
    //
    // The publication starts private until its initial state has been committed atomically.
    mtd open(root: string, privateMode = true) fail
    {
        Swag.assert(.data == null)
        let resolved = mountPrivacyPathNative(root)
        if resolved.isEmpty() do
            fail Errors.BadParameterError{}
        .channel = mountPrivacyChannel(resolved)
        try .openNative()
        let data = unwrap .data
        Atomic.exchange(&data.instance, Hash.hash64(Guid64.random()) | 1)
        Atomic.exchange(&data.activation, 1)
        Atomic.exchange(&data.flags, privateMode ? 3'u64 : 2'u64)
        Atomic.exchange(&data.sequence, 2)
    }

    // Applies the owner's current mode to this live mount.
    mtd setPrivateMode(privateMode: bool)
    {
        .mutex.lock()
        defer .mutex.unlock()
        if not .data do
            return
        let data  = .data
        let flags = Atomic.get(&data.flags)
        if ((flags & 1) != 0) == privateMode do
            return
        Atomic.add(&data.sequence, 1)
        if privateMode do
            Atomic.add(&data.activation, 1)
        Atomic.exchange(&data.flags, privateMode ? 3'u64 : 2'u64)
        Atomic.add(&data.sequence, 1)
    }

    // Withdraws the publication. Existing snapshots retain its final policy and activation.
    mtd close()
    {
        .mutex.lock()
        defer .mutex.unlock()
        if not .data do
            return
        Atomic.exchange(&.data.flags, Atomic.get(&.data.flags) & 1)
        .closeNative()
    }

    // Withdraws the publication when its owner leaves scope.
    mtd opDrop() { .close() }
}

internal func readMountPrivacyData(data: *MountPrivacyData, result: *MountPrivacy)->bool
{
    for 8
    {
        let sequence = Atomic.get(&data.sequence)
        if not sequence or sequence & 1 do
            continue
        let instance   = Atomic.get(&data.instance)
        let activation = Atomic.get(&data.activation)
        let flags      = Atomic.get(&data.flags)
        if sequence != Atomic.get(&data.sequence) do
            continue
        result.instance    = instance
        result.activation  = activation
        result.privateMode = (flags & 1) != 0
        return true
    }

    return false
}

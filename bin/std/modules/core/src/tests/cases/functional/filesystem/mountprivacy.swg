#global if #command == Swag.CompilerCommand.Test
#global private

// Reader copies retain the final policy after close. A normal public unmount does not invent
// a private activation; a private activation immediately followed by close is still observable.
#test
{
    let root = CoreTests.makeFilesystemTestPath("mount_privacy_terminal")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    var reader = File.MountPrivacy.query(root)
    var copy   = reader
    publisher.close()
    discard copy.refresh()
    Swag.require(not copy.privateMode)
    expect publisher.open(root, false)
    reader = File.MountPrivacy.query(root)
    copy   = reader
    let activation = copy.activation
    publisher.setPrivateMode(true)
    publisher.close()
    discard copy.refresh()
    Swag.require(copy.privateMode and copy.activation > activation)
}

#premain
{
    let arguments = Env.arguments()
    if arguments.count >= 4 and arguments[1] == "--swag-mount-privacy-peer"
    {
        let policy   = File.MountPrivacy.query(arguments[2])
        let expected = arguments[3] == "private"
        Env.exit(not policy.root.isEmpty() and policy.privateMode == expected ? 37 : 1)
    }
}

// A separate native process discovers the same publication through the filesystem path.
#test
{
    Swag.require(not Swag.jit(), "run the mount policy peer with --no-test-jit")
    let root = CoreTests.makeFilesystemTestPath("mount_privacy_process")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    let sandbox = Format.toString("swag.sandbox=%", Env.sandboxRoot())
    for mode in ["public", "private", "public"]
    {
        publisher.setPrivateMode(mode == "private")
        let arguments = ["--swag-mount-privacy-peer", root.toString(), mode, sandbox.toString()]
        let peer      = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(), arguments: arguments,
                                                            standardOutput: .Pipe, standardError: .Pipe})
        Swag.require(peer.exitCode() == 37, String.from(peer.standardError()).toString())
    }
}

struct PrivacyReadThread
{
    policy: File.MountPrivacy
    ready:  u32
    stop:   u32
    reads:  u32
}

func readPolicies(thread: const *Threading.Thread)
{
    let state = cast(*PrivacyReadThread, unwrap thread.userParam)
    Atomic.exchange(&state.ready, 1)
    var activation = state.policy.activation
    while not Atomic.get(&state.stop)
    {
        discard state.policy.refresh()
        Swag.require(state.policy.activation >= activation)
        activation = state.policy.activation
        Atomic.add(&state.reads, 1)
    }
}

// Concurrent readers never observe a torn activation counter during mode changes.
#test
{
    let root = CoreTests.makeFilesystemTestPath("mount_privacy_concurrent")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    var state = PrivacyReadThread{policy: File.MountPrivacy.query(root)}
    var reader: Threading.Thread
    discard expect reader.init(&readPolicies, &state)
    discard expect reader.start()
    while not Atomic.get(&state.ready) do
        Threading.Thread.sleep(1'ms)
    for 1000
    {
        publisher.setPrivateMode(true)
        publisher.setPrivateMode(false)
    }

    while not Atomic.get(&state.reads) do
        Threading.Thread.sleep(1'ms)
    Atomic.exchange(&state.stop, 1)
    reader.wait()
    discard state.policy.refresh()
    Swag.require(not state.policy.privateMode and state.policy.activation == 1001)
}

// Independent handles see updates, rapid toggles, and the loss of a publication.
#test
{
    let root = CoreTests.makeFilesystemTestPath("mount_privacy")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    let nested = Path.combine(root, "nested")
    expect Directory.create(nested)
    Swag.require(File.MountPrivacy.query(nested).root.isEmpty())
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    defer publisher.close()
    var reader = File.MountPrivacy.query(nested)
    Swag.require(not reader.root.isEmpty() and not reader.privateMode and reader.instance != 0)
    let epoch = reader.activation
    publisher.setPrivateMode(true)
    publisher.setPrivateMode(false)
    Swag.require(reader.refresh() and not reader.privateMode and reader.activation > epoch)
    publisher.setPrivateMode(true)
    Swag.require(reader.refresh() and reader.privateMode)
    publisher.close()
    Swag.require(not reader.root.isEmpty())
    discard reader.refresh()
    Swag.require(reader.privateMode)
}

// A second owner cannot change the live publisher's policy.
#test
{
    let root = CoreTests.makeFilesystemTestPath("mount_privacy_owner")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    var first: File.MountPrivacyPublisher
    expect first.open(root, false)
    defer first.close()
    var second: File.MountPrivacyPublisher
    var error:  Swag.Error
    discard catch second.open(root, true) as error
    Swag.require(error.value() != null)
    Swag.require(not File.MountPrivacy.query(root).privateMode)
}

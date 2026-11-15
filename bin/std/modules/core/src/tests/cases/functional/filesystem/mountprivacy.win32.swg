#global if #command == Swag.CompilerCommand.Test and WINDOWS
#global private

// A junction into a private root uses the target publication, including through a missing leaf.
#test
{
    let root = CoreTests.makeFilesystemTestPath("privacy_target")
    let link = CoreTests.makeFilesystemTestPath("privacy_junction")
    expect Directory.create(root)
    defer expect Directory.delete(root, recurse: true)
    let shell      = Path.combine(Path.directoryName(Env.realSpecialDirectory(.Font)), "System32", "cmd.exe")
    var nativeLink = String.from(link)
    var nativeRoot = String.from(root)
    nativeLink.replace('/', "\\")
    nativeRoot.replace('/', "\\")
    let arguments = ["/c", "mklink", "/J", nativeLink.toString(), nativeRoot.toString()]
    let created   = expect Env.runProcess(Env.StartInfo{fileName: shell.toString(), arguments: arguments,
                                                        standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(created.exitCode() == 0, String.from(created.standardError()).toString())
    defer expect Directory.delete(link)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root)
    let direct = File.MountPrivacy.query(root)
    let linked = File.MountPrivacy.query(Path.combine(link, "missing.txt"))
    Swag.require(linked.privateMode and direct.channel == linked.channel and direct.instance == linked.instance)
}

// WinFsp's final UNC name identifies a Vault mount even when its publisher cannot be read.
#test
{
    let root = File.mountPrivacyProtectedRootNative(#raw "\\?\UNC\SWAGVAULT\12345\folder\file.txt")
    Swag.require(Path.equals(root, #raw "\\?\UNC\swagvault\12345"))
    Swag.require(File.mountPrivacyProtectedRootNative(#raw "\\?\UNC\server\public\file.txt").isEmpty())
}

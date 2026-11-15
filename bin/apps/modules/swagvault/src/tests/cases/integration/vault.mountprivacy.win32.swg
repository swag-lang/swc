#global if WINDOWS and #hastag("vault.integration")

using Core

namespace Integration
{
    // Exercise the real WinFsp identity with a file handle held across all transitions.
    #[Swag.Propagate]
    func runPrivacyScenarios(box: *Sandbox, file: string) fail
    {
        let unresolved = File.MountPrivacy.query(file)
        verify(unresolved.privateMode and not unresolved.root.isEmpty(), "a Vault mount without a publication must suppress history")
        var publisher: File.MountPrivacyPublisher
        publisher.open(driveRoot(box.mountPoint), false)
        var reader = File.MountPrivacy.query(file)
        verify(not reader.privateMode and reader.instance != 0, "a public Vault mount must permit history")
        var openFile   = File.open(file, .Open, .Read, .ReadWrite)
        let activation = reader.activation
        publisher.setPrivateMode(true)
        discard reader.refresh()
        verify(reader.privateMode and reader.activation > activation, "a live Vault switch must make an open file private")
        verify(openFile.size() == 7, "changing privacy must preserve the open file handle")
        publisher.setPrivateMode(false)
        discard reader.refresh()
        verify(not reader.privateMode, "turning privacy off must allow future history")
        let previous = reader.activation
        publisher.setPrivateMode(true)
        publisher.setPrivateMode(false)
        discard reader.refresh()
        verify(reader.activation > previous and not reader.privateMode, "a fast privacy cycle must remain observable")
        publisher.close()
        discard reader.refresh()
        verify(not reader.privateMode, "closing a public mount must preserve public history")
        publisher.open(driveRoot(box.mountPoint), false)
        reader = File.MountPrivacy.query(file)
        publisher.setPrivateMode(true)
        publisher.close()
        discard reader.refresh()
        verify(reader.privateMode, "an activation followed by unmount must suppress late saves")
    }
}

#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The window publishes its current policy to existing mounts without rebuilding them.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault-policy-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let mount  = Memory.new'MountedVault()
    expect mount.privacy.open(root)
    window.mountedDrives.drives.add({volume: mount, path: "test-vault", drive: root})
    var reader = File.MountPrivacy.query(root)
    Swag.require(reader.privateMode)
    window.privacyMode = false
    window.publishMountPrivacy()
    discard reader.refresh()
    Swag.require(not reader.privateMode)
    let activation = reader.activation
    window.privacyMode = true
    window.publishMountPrivacy()
    discard reader.refresh()
    Swag.require(reader.privateMode and reader.activation > activation)
    window.privacyMode = false
    window.publishMountPrivacy()
    let detached = window.mountedDrives.detach(0)
    Swag.require(detached == mount)
    discard reader.refresh()
    Swag.require(not reader.privateMode)
    Memory.delete(mount)
}

#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

#[Swag.TestTag("integration.filesystem")]
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-cache-root-%", Guid64.random()))
    let target = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-cache-target-%", Guid64.random()))
    expect Directory.create(root)
    expect Directory.create(target)
    defer expect Directory.delete(root, recurse: true)
    defer expect Directory.delete(target, recurse: true)

    var digest: String
    for 64 do
        digest += "A"
    let link = Path.combine(root, Format.toString("Swag.MountPrivacy.1.%.1.1", digest.toString()))
    let cached = Path.combine(target, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.png")
    discard expect File.writeAllText(cached, "keep")
    Swag.require(Linux.symlinkat(target.storage(), Linux.AT_FDCWD, link.storage()) == 0)
    defer discard Linux.unlinkat(Linux.AT_FDCWD, link.storage(), 0)

    discard expect ThumbnailCache.prune(root, Time.Timestamp.utcNow().ticks + 121 * Time.TicksPerDay)
    Swag.require(File.exists(cached))
    Swag.require((expect ThumbnailCache.clear(root)) == 0)
    Swag.require(File.exists(cached))
}

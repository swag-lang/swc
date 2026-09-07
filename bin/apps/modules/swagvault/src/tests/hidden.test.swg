#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func hiddenTestPath()->String => Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault_hidden_%.bin", Guid64.random()))

#test
{
    let path = hiddenTestPath()
    defer discard catch File.delete(path)
    const OuterPassword = "outer access"
    const InnerPassword = "hidden access"
    const OuterSize     = DataOffset + 256 * BlockRecordSize
    const HiddenSize    = DataOffset + 64 * BlockRecordSize
    var outer = expect Volume.create(path, OuterPassword, OuterSize)
    let decoy = expect outer.createNode("\\decoy.txt", false, FileAttributeNormal, "")
    Swag.assert(expect outer.writeNode(decoy, 0, "outer bytes", false, false) == 11)
    outer.close()
    var hidden = expect Volume.createHidden(path, OuterPassword, InnerPassword, HiddenSize)
    let first  = hidden.file.base
    let last   = first + hidden.file.limit
    let secret = expect hidden.createNode("\\secret.txt", false, FileAttributeNormal, "")
    Swag.assert(expect hidden.writeNode(secret, 0, "hidden bytes", false, false) == 12)
    hidden.close()

    var protected = expect Volume.open(path, OuterPassword, protectionPassword: InnerPassword)
    Swag.assert(protected.resolve("\\secret.txt") == null)
    Swag.assert(protected.resolve("\\decoy.txt") != null)
    Swag.assert(protected.file.protectedFirst == first and protected.file.protectedEnd == last)

    // Every path, including metadata, batched data, and camouflage, meets this storage boundary.
    var byte: [1] u8 = [42]
    expect protected.file.writeAllAt(first - 1, byte)
    discard catch protected.file.writeAllAt(first, byte) as collision
    Swag.assert(collision != null and protected.file.protectionTriggered)
    discard catch protected.requireWritable() as later
    Swag.assert(later != null)
    protected.close()

    var reopened = expect Volume.open(path, InnerPassword)
    Swag.assert(reopened.file.base == first)
    let node = reopened.resolve("\\secret.txt")!
    var data: [12] u8
    Swag.assert(expect reopened.readNode(node.id, 0, data) == data.count)
    Swag.assert(Core.Crypto.constantTimeEqual(data, "hidden bytes"))

    // An existing alternate slot also needs a working locator before old access is revoked.
    let alternate = expect reopened.addPassword("replacement hidden access")
    expect HiddenLocator.erase(&reopened.file.stream, alternate)
    expect reopened.changePassword(InnerPassword, "replacement hidden access")
    reopened.close()
    discard catch Volume.open(path, InnerPassword) as revoked
    Swag.assert(revoked != null)
    var changed = expect Volume.open(path, "replacement hidden access", true)
    Swag.assert(changed.resolve("\\secret.txt") != null)
    changed.close()

    var regular = expect Volume.open(path, OuterPassword)

    // Revoking an outer key slot preserves its independent hidden locator.
    expect regular.changePassword(OuterPassword, "new outer access")
    regular.close()
    var afterRotation = expect Volume.open(path, "replacement hidden access", true)
    Swag.assert(afterRotation.resolve("\\secret.txt") != null)
    afterRotation.close()
}

#test
{
    let path = hiddenTestPath()
    defer discard catch File.delete(path)
    var outer = expect Volume.create(path, "outer", DataOffset + 256 * BlockRecordSize)
    outer.close()
    discard catch Volume.createHidden(path, "outer", "outer", MinimumSize) as same
    Swag.assert(same != null)
    discard catch Volume.createHidden(path, "outer", "", MinimumSize) as empty
    Swag.assert(empty != null)
    discard catch Volume.createHidden(path, "outer", "hidden", DataOffset + 256 * BlockRecordSize) as full
    Swag.assert(full != null)
    discard catch Volume.createHidden(path, "outer", "hidden", Swag.U64.Max) as overflow
    Swag.assert(overflow != null)
    var canceled: VolumeProgress
    canceled.begin(0)
    canceled.cancel()
    discard catch Volume.createHidden(path, "outer", "hidden", MinimumSize, &canceled) as cancellation
    Swag.assert(cancellation != null)
    var hidden = expect Volume.createHidden(path, "outer", "hidden", MinimumSize)
    discard catch hidden.grow(MinimumSize * 2) as grow
    Swag.assert(grow != null)
    discard catch hidden.file.writeAllAt(hidden.file.limit, "x") as bounds
    Swag.assert(bounds != null)
    hidden.close()
    discard catch Volume.open(path, "outer", protectionPassword: "incorrect") as wrong
    Swag.assert(wrong != null)
    var protected = expect Volume.open(path, "outer", protectionPassword: "hidden")
    discard catch protected.shrink(MinimumSize) as shrink
    Swag.assert(shrink != null)
    discard catch protected.reapplyCamouflage() as camouflage
    Swag.assert(camouflage != null)
    protected.close()
}

// Normal mounts retain their free count and can consume the hidden region. Protection changes
// neither allocation nor accounting; it refuses the physical write only when requested.
#test
{
    let path = hiddenTestPath()
    defer discard catch File.delete(path)
    var outer      = expect Volume.create(path, "outer", DataOffset + 256 * BlockRecordSize)
    let freeBefore = outer.freeBytes()
    outer.close()
    var hidden = expect Volume.createHidden(path, "outer", "hidden", DataOffset + 80 * BlockRecordSize)
    hidden.close()
    var normal = expect Volume.open(path, "outer")
    Swag.assert(normal.freeBytes() == freeBefore)
    Swag.assert(normal.file.protectedEnd == 0)
    let file = expect normal.createNode("\\ordinary.bin", false, FileAttributeNormal, "")
    var data: Array'u8
    data.resize(180 * BlockSize)
    Swag.assert(expect normal.writeNode(file, 0, data.toSlice(), false, false) == data.count)
    expect normal.commit()
    normal.close()

    // These writes reached the hidden header: without the option, they deliberately succeed.
    discard catch Volume.open(path, "hidden") as overwritten
    Swag.assert(overwritten != null)
    var reopened = expect Volume.open(path, "outer", true)
    Swag.assert(reopened.resolve("\\ordinary.bin")!.size == data.count)
    reopened.close()
}

#test
{
    let path    = hiddenTestPath()
    let keyPath = hiddenTestPath()
    defer discard catch File.delete(path)
    defer discard catch File.delete(keyPath)
    expect File.writeAllBytes(keyPath, "key-file bytes")
    var files: Array'String
    files.add(keyPath)
    var access: VaultAccess
    access.setInputs("hidden password", files.toSlice())
    var credential = expect access.derive()
    var outer      = expect Volume.create(path, "outer", DataOffset + 256 * BlockRecordSize)
    outer.close()
    discard catch Volume.createHidden(path, "outer", credential.toSlice(), MinimumSize, outerReserve: 256 * BlockSize) as reserve
    Swag.assert(reserve != null)
    var hidden = expect Volume.createHidden(path, "outer", credential.toSlice(), MinimumSize)
    let file   = expect hidden.createNode("\\secret", false, FileAttributeNormal, "")
    Swag.assert(expect hidden.writeNode(file, 0, "secret", false, false) == 6)
    hidden.close()
    discard catch Volume.open(path, "hidden password") as missingKey
    Swag.assert(missingKey != null)
    var protected = expect Volume.open(path, "outer", protectionPassword: credential.toSlice())
    let ordinary  = expect protected.createNode("\\ordinary", false, FileAttributeNormal, "")
    var data: Array'u8
    data.resize(16 * BlockSize)
    var offset = 0'u64
    var collision: any?
    for 32
    {
        discard catch protected.writeNode(ordinary, offset, data.toSlice(), false, false) as error
        if error != null
        {
            collision = error
            break
        }

        expect protected.commit()
        offset += data.count
    }

    Swag.assert(offset > 0 and collision != null and protected.file.protectionTriggered)
    protected.close()
    var reopened = expect Volume.open(path, credential.toSlice(), true)
    var bytes: [6] u8
    Swag.assert(expect reopened.readNode(reopened.resolve("\\secret")!.id, 0, bytes) == bytes.count)
    Swag.assert(Core.Crypto.constantTimeEqual(bytes, "secret"))
    reopened.close()
    expect File.writeAllBytes(keyPath, "changed key-file bytes")
    var changed = expect access.derive()
    discard catch Volume.open(path, "outer", protectionPassword: changed.toSlice()) as wrongKey
    Swag.assert(wrongKey != null)
}

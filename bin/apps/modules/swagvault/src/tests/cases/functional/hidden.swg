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
    var outer        = expect Volume.create(path, OuterPassword, OuterSize)
    let decoy        = expect outer.createNode("\\decoy.txt", false, FileAttributeNormal, "")
    let bytesWritten = expect outer.writeNode(decoy, 0, "outer bytes", false, false)
    Swag.require(bytesWritten == 11)
    outer.close()
    var hidden        = expect Volume.createHidden(path, OuterPassword, InnerPassword, HiddenSize)
    let first         = hidden.file.base
    let last          = first + hidden.file.limit
    let secret        = expect hidden.createNode("\\secret.txt", false, FileAttributeNormal, "")
    let bytesWritten2 = expect hidden.writeNode(secret, 0, "hidden bytes", false, false)
    Swag.require(bytesWritten2 == 12)
    hidden.close()

    var protected = expect Volume.open(path, OuterPassword, protectionPassword: InnerPassword)
    Swag.require(protected.resolve("\\secret.txt") == null)
    Swag.require(protected.resolve("\\decoy.txt") != null)
    Swag.require(protected.file.protectedFirst == first and protected.file.protectedEnd == last)

    // Every path, including metadata, batched data, and camouflage, meets this storage boundary.
    var byte: [1] u8 = [42]
    expect protected.file.writeAllAt(first - 1, byte)
    var collisionOutcome: Swag.Error
    discard catch protected.file.writeAllAt(first, byte) as collisionOutcome
    let collision = collisionOutcome.value()
    Swag.require(collision != null and protected.file.protectionTriggered)
    var laterOutcome: Swag.Error
    discard catch protected.requireWritable() as laterOutcome
    let later = laterOutcome.value()
    Swag.require(later != null)
    protected.close()

    var reopened = expect Volume.open(path, InnerPassword)
    Swag.require(reopened.file.base == first)
    let node      = unwrap reopened.resolve("\\secret.txt")
    var data: [12] u8
    let bytesRead = expect reopened.readNode(node.id, 0, data)
    Swag.require(bytesRead == data.count)
    Swag.require(Core.Crypto.constantTimeEqual(data, "hidden bytes"))

    // An existing alternate slot also needs a working locator before old access is revoked.
    let alternate = expect reopened.addPassword("replacement hidden access")
    expect HiddenLocator.erase(&reopened.file.stream, alternate)
    expect reopened.changePassword(InnerPassword, "replacement hidden access")
    reopened.close()
    var revokedOutcome: Swag.Error
    discard catch Volume.open(path, InnerPassword) as revokedOutcome
    let revoked = revokedOutcome.value()
    Swag.require(revoked != null)
    var changed = expect Volume.open(path, "replacement hidden access", true)
    Swag.require(changed.resolve("\\secret.txt") != null)
    changed.close()

    var regular = expect Volume.open(path, OuterPassword)

    // Revoking an outer key slot preserves its independent hidden locator.
    expect regular.changePassword(OuterPassword, "new outer access")
    regular.close()
    var afterRotation = expect Volume.open(path, "replacement hidden access", true)
    Swag.require(afterRotation.resolve("\\secret.txt") != null)
    afterRotation.close()
}

#test
{
    let path = hiddenTestPath()
    defer discard catch File.delete(path)
    var outer = expect Volume.create(path, "outer", DataOffset + 256 * BlockRecordSize)
    outer.close()
    var sameOutcome: Swag.Error
    discard catch Volume.createHidden(path, "outer", "outer", MinimumSize) as sameOutcome
    let same = sameOutcome.value()
    Swag.require(same != null)
    var emptyOutcome: Swag.Error
    discard catch Volume.createHidden(path, "outer", "", MinimumSize) as emptyOutcome
    let empty = emptyOutcome.value()
    Swag.require(empty != null)
    var fullOutcome: Swag.Error
    discard catch Volume.createHidden(path, "outer", "hidden", DataOffset + 256 * BlockRecordSize) as fullOutcome
    let full = fullOutcome.value()
    Swag.require(full != null)
    var overflowOutcome: Swag.Error
    discard catch Volume.createHidden(path, "outer", "hidden", Swag.U64.Max) as overflowOutcome
    let overflow = overflowOutcome.value()
    Swag.require(overflow != null)
    var canceled: VolumeProgress
    canceled.begin(0)
    canceled.cancel()
    var cancellationOutcome: Swag.Error
    discard catch Volume.createHidden(path, "outer", "hidden", MinimumSize, &canceled) as cancellationOutcome
    let cancellation = cancellationOutcome.value()
    Swag.require(cancellation != null)
    var hidden = expect Volume.createHidden(path, "outer", "hidden", MinimumSize)
    var growOutcome: Swag.Error
    discard catch hidden.grow(MinimumSize * 2) as growOutcome
    let grow = growOutcome.value()
    Swag.require(grow != null)
    var boundsOutcome: Swag.Error
    discard catch hidden.file.writeAllAt(hidden.file.limit, "x") as boundsOutcome
    let bounds = boundsOutcome.value()
    Swag.require(bounds != null)
    hidden.close()
    var wrongOutcome: Swag.Error
    discard catch Volume.open(path, "outer", protectionPassword: "incorrect") as wrongOutcome
    let wrong = wrongOutcome.value()
    Swag.require(wrong != null)
    var protected = expect Volume.open(path, "outer", protectionPassword: "hidden")
    var shrinkOutcome: Swag.Error
    discard catch protected.shrink(MinimumSize) as shrinkOutcome
    let shrink = shrinkOutcome.value()
    Swag.require(shrink != null)
    var camouflageOutcome: Swag.Error
    discard catch protected.reapplyCamouflage() as camouflageOutcome
    let camouflage = camouflageOutcome.value()
    Swag.require(camouflage != null)
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
    Swag.require(normal.freeBytes() == freeBefore)
    Swag.require(normal.file.protectedEnd == 0)
    let file = expect normal.createNode("\\ordinary.bin", false, FileAttributeNormal, "")
    var data: Array'u8
    data.resize(180 * BlockSize)
    let bytesWritten = expect normal.writeNode(file, 0, data.toSlice(), false, false)
    Swag.require(bytesWritten == data.count)
    expect normal.commit()
    normal.close()

    // These writes reached the hidden header: without the option, they deliberately succeed.
    var overwrittenOutcome: Swag.Error
    discard catch Volume.open(path, "hidden") as overwrittenOutcome
    let overwritten = overwrittenOutcome.value()
    Swag.require(overwritten != null)
    var reopened = expect Volume.open(path, "outer", true)
    Swag.require(reopened.resolve("\\ordinary.bin")!.size == data.count)
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
    var reserveOutcome: Swag.Error
    discard catch Volume.createHidden(path, "outer", credential.toSlice(), MinimumSize, outerReserve: 256 * BlockSize) as reserveOutcome
    let reserve = reserveOutcome.value()
    Swag.require(reserve != null)
    var hidden       = expect Volume.createHidden(path, "outer", credential.toSlice(), MinimumSize)
    let file         = expect hidden.createNode("\\secret", false, FileAttributeNormal, "")
    let bytesWritten = expect hidden.writeNode(file, 0, "secret", false, false)
    Swag.require(bytesWritten == 6)
    hidden.close()
    var missingKeyOutcome: Swag.Error
    discard catch Volume.open(path, "hidden password") as missingKeyOutcome
    let missingKey = missingKeyOutcome.value()
    Swag.require(missingKey != null)
    var protected = expect Volume.open(path, "outer", protectionPassword: credential.toSlice())
    let ordinary  = expect protected.createNode("\\ordinary", false, FileAttributeNormal, "")
    var data: Array'u8
    data.resize(16 * BlockSize)
    var offset    = 0'u64
    var collision = false
    for 32
    {
        discard catch protected.writeNode(ordinary, offset, data.toSlice(), false, false)
        {
            collision = true
            break
        }

        expect protected.commit()
        offset += data.count
    }

    Swag.require(offset > 0 and collision and protected.file.protectionTriggered)
    protected.close()
    var reopened  = expect Volume.open(path, credential.toSlice(), true)
    var bytes: [6] u8
    let bytesRead = expect reopened.readNode(reopened.resolve("\\secret")!.id, 0, bytes)
    Swag.require(bytesRead == bytes.count)
    Swag.require(Core.Crypto.constantTimeEqual(bytes, "secret"))
    reopened.close()
    expect File.writeAllBytes(keyPath, "changed key-file bytes")
    var changed = expect access.derive()
    var wrongKeyOutcome: Swag.Error
    discard catch Volume.open(path, "outer", protectionPassword: changed.toSlice()) as wrongKeyOutcome
    let wrongKey = wrongKeyOutcome.value()
    Swag.require(wrongKey != null)
}

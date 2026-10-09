impl Volume
{
    // Finds the key slot `password` opens and unwraps the master key from it.
    //
    // The complete area shares one salt, so rejecting a password costs exactly
    // one fixed Argon2id derivation followed by four authenticated opens.
    mtd unlock(password: const [..] u8) fail
    {
        var area: [KeySlotAreaSize] u8
        defer Core.Crypto.secureClear(area)
        if not (try .file.readExactAt(KeySlotAreaOffset, area)) do
            fail volumeError(.PasswordOrDamaged)

        Swag.memcpy(&.slotSalt[0], &area[0], Crypto.SaltSize)
        var slotKey = try Crypto.deriveSlotKey(password, .slotSalt)
        defer Core.Crypto.secureClear(slotKey)
        var candidate: [Crypto.MasterKeySize] u8
        defer Core.Crypto.secureClear(candidate)
        var found = false
        for index in KeySlotCount
        {
            Core.Crypto.secureClear(candidate)
            var slot = KeySlot.decode(area[index * KeySlotSize + KeySlotPrefixSize until (index + 1) * KeySlotSize])
            defer slot.clear()
            if try slot.unwrap(slotKey, index, candidate)
            {
                Swag.memcpy(&.master[0], &candidate[0], Crypto.MasterKeySize)
                found = true
            }
        }

        if not found do
            fail volumeError(.PasswordOrDamaged)
        .keys = try Crypto.deriveKeys(.master)
    }

    // Writes the key slot at `index` so that `password` unwraps the master key.
    mtd writeKeySlot(index: u64, password: const [..] u8) fail
    {
        try .requireWritable()
        var slotKey = try Crypto.deriveSlotKey(password, .slotSalt)
        defer Core.Crypto.secureClear(slotKey)
        var slot = try KeySlot.create(slotKey, .master, index)
        defer slot.clear()
        let record = try slot.encode()
        try .file.writeAllAt(keySlotPayloadOffset(index), record[until KeySlotPlainSize])
        try .file.flush()
        if .file.base
        {
            try HiddenLocator.write(&.file.stream, index, password, {.file.base, .file.limit})
            let verified = try HiddenLocator.find(&.file.stream, password)
            if verified.first != .file.base or verified.count != .file.limit do
                fail volumeError(.Io)
        }
    }

    // Overwrites the key slot at `index` with random bytes, so the password it
    // held no longer opens the container.
    mtd eraseKeySlot(index: u64) fail
    {
        try .requireWritable()
        var record: [KeySlotPayloadSize] u8
        try Core.Crypto.randomBytes(record)
        try .file.writeAllAt(keySlotPayloadOffset(index), record[until KeySlotPlainSize])
        try .file.flush()
        if .file.base do
            try HiddenLocator.erase(&.file.stream, index)
    }

    // Reports which slot `password` opens, or `Swag.U64.Max` when none does.
    mtd findKeySlot(password: const [..] u8)->u64 fail
    {
        var area: [KeySlotAreaSize] u8
        defer Core.Crypto.secureClear(area)
        if not (try .file.readExactAt(KeySlotAreaOffset, area)) do
            return Swag.U64.Max

        var slotKey = try Crypto.deriveSlotKey(password, .slotSalt)
        defer Core.Crypto.secureClear(slotKey)
        var candidate: [Crypto.MasterKeySize] u8
        defer Core.Crypto.secureClear(candidate)
        for index in KeySlotCount
        {
            Core.Crypto.secureClear(candidate)
            var slot = KeySlot.decode(area[index * KeySlotSize + KeySlotPrefixSize until (index + 1) * KeySlotSize])
            defer slot.clear()
            if try slot.unwrap(slotKey, index, candidate) do
                return index
        }

        return Swag.U64.Max
    }

    // Replaces the access bytes of the slot `current` opens.
    //
    // A fresh slot is written and read back before the current one is erased. The master key,
    // and therefore every encrypted block in the container, stays untouched; an interrupted
    // rotation always leaves at least one verified way to unwrap it.
    //
    // An empty `replacement` removes the protection: the slot then unwraps under the
    // empty password, which is how a container stops asking for one. That is a
    // deliberate downgrade a caller states outright, unlike [[Volume.addPassword]],
    // which refuses to add an unprotected way into a container that has one.
    mtd changePassword(current, replacement: const [..] u8) fail
    {
        try .requireWritable()
        if .file.base and (not replacement.count or (try HiddenLocator.opensOuter(&.file.stream, replacement))) do
            fail volumeError(.InvalidInput)

        let currentIndex = try .findKeySlot(current)
        if currentIndex == Swag.U64.Max do
            fail volumeError(.AccessDenied)

        let existingReplacement = try .findKeySlot(replacement)
        if existingReplacement == currentIndex do
            return

        var replacementIndex = existingReplacement
        if replacementIndex == Swag.U64.Max
        {
            for index in KeySlotCount where (.keySlotMask & keySlotBit(index)) == 0
            {
                replacementIndex = index
                break
            }

            if replacementIndex == Swag.U64.Max do
                fail volumeError(.DiskFull)

            // Reserve before writing. A stopped write may waste this slot, but it cannot expose
            // the current one to reuse or make the vault lose its existing access.
            .keySlotMask  |= keySlotBit(replacementIndex)
            .scalarsDirty = true
            .dirty        = true
            try .checkpoint()
            try .writeKeySlot(replacementIndex, replacement)

            if (try .findKeySlot(replacement)) != replacementIndex do
                fail volumeError(.Io)
        }

        // An already occupied hidden slot can have lost its locator independently. Repair and
        // verify that access before revoking the current one as well.
        if .file.base and existingReplacement != Swag.U64.Max do
            try .writeKeySlot(replacementIndex, replacement)

        // Only a verified replacement makes the previous access removable.
        try .eraseKeySlot(currentIndex)
        .keySlotMask  &= ~keySlotBit(currentIndex)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
    }

    // Adds `additional` as another password that opens this container.
    //
    // Which slots are in use cannot be read from the slot area itself: an unused
    // slot and a slot whose password is unknown are the same random bytes, which
    // is exactly the property that hides how many passwords exist. The container
    // therefore keeps the record in its encrypted header instead.
    // An empty `additional` is refused: a second way in that needs no password would
    // undo the protection of every other slot without saying so. Removing the
    // protection is [[Volume.changePassword]] with an empty replacement.
    mtd addPassword(additional: const [..] u8)->u64 fail
    {
        try .requireWritable()
        if .file.base and (not additional.count or (try HiddenLocator.opensOuter(&.file.stream, additional))) do
            fail volumeError(.InvalidInput)

        if not additional.count do
            fail volumeError(.PasswordRequired)
        if (try .findKeySlot(additional)) != Swag.U64.Max do
            fail volumeError(.AlreadyExists)

        for index in KeySlotCount where (.keySlotMask & keySlotBit(index)) == 0
        {
            // The slot is reserved before it is written, so an interrupted add
            // wastes a slot instead of letting a later one overwrite a password
            // that already works.
            .keySlotMask  |= keySlotBit(index)
            .scalarsDirty = true
            .dirty        = true
            try .checkpoint()
            try .writeKeySlot(index, additional)
            return index
        }

        fail volumeError(.DiskFull)
    }

    // Removes the password that opens a slot.
    //
    // The last remaining password cannot be removed: a container no password
    // opens is unrecoverable, and there is no reason to offer that.
    mtd removePassword(password: const [..] u8) fail
    {
        try .requireWritable()
        let index = try .findKeySlot(password)
        if index == Swag.U64.Max do
            fail volumeError(.NotFound)
        if .keySlotCount() <= 1 do
            fail volumeError(.AccessDenied)

        try .eraseKeySlot(index)
        .keySlotMask  &= ~keySlotBit(index)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
    }

    // Number of passwords that currently open this container.
    mtd const keySlotCount()->u64 => Swag.bitCountNz(.keySlotMask)
}

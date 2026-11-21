#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func accessTestPassword()->const [..] u8 => "panel password"
func accessTestPath(tag: string)->String => Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("vault_access_%_%.bin", tag, Guid64.random()))

// Password-only access uses the password bytes directly.
#test
{
    var files:  Array'String
    var access: VaultAccess
    access.setInputs(accessTestPassword(), files.toSlice())

    var credential = expect access.derive()
    Swag.require(Slice.equals(credential.toSlice(), accessTestPassword()))
}

// Key-file contents, lengths, order, and password all participate; paths do not.
#test
{
    let firstPath = accessTestPath("first")
    defer discard catch File.delete(firstPath)
    let movedPath = accessTestPath("moved")
    defer discard catch File.delete(movedPath)
    let secondPath = accessTestPath("second")
    defer discard catch File.delete(secondPath)

    discard expect File.writeAllBytes(firstPath, [1'u8, 2, 3, 4])
    discard expect File.writeAllBytes(movedPath, [1'u8, 2, 3, 4])
    discard expect File.writeAllBytes(secondPath, [5'u8, 6, 7])

    var firstFiles: Array'String
    firstFiles.add(firstPath)
    firstFiles.add(secondPath)
    var first: VaultAccess
    first.setInputs(accessTestPassword(), firstFiles.toSlice())
    var firstCredential = expect first.derive()

    var movedFiles: Array'String
    movedFiles.add(movedPath)
    movedFiles.add(secondPath)
    var moved: VaultAccess
    moved.setInputs(accessTestPassword(), movedFiles.toSlice())
    var movedCredential = expect moved.derive()
    Swag.require(Slice.equals(firstCredential.toSlice(), movedCredential.toSlice()))

    var reversedFiles: Array'String
    reversedFiles.add(secondPath)
    reversedFiles.add(firstPath)
    var reversed: VaultAccess
    reversed.setInputs(accessTestPassword(), reversedFiles.toSlice())
    var reversedCredential = expect reversed.derive()
    Swag.require(not Slice.equals(firstCredential.toSlice(), reversedCredential.toSlice()))

    var otherPassword: VaultAccess
    otherPassword.setInputs("different", firstFiles.toSlice())
    var otherCredential = expect otherPassword.derive()
    Swag.require(not Slice.equals(firstCredential.toSlice(), otherCredential.toSlice()))
}

// The stored credential binds chunk order, the final partial chunk, and empty key files.
#test
{
    let keyPath = accessTestPath("chunks")
    defer discard catch File.delete(keyPath)
    let emptyPath = accessTestPath("empty")
    defer discard catch File.delete(emptyPath)

    var bytes: Array'u8
    bytes.resize(8 * 1024 * 1024 + 3)
    bytes[0] = 42
    bytes[1024 * 1024]     = 17
    bytes[bytes.count - 1] = 99
    discard expect File.writeAllBytes(keyPath, bytes.toSlice())
    discard expect File.writeAllBytes(emptyPath, "")

    var files: Array'String
    files.add(keyPath)
    files.add(emptyPath)
    var access: VaultAccess
    access.setInputs("", files.toSlice())
    let credential = expect access.derive()

    // BLAKE2b vector computed independently from the credential format.
    const Expected: [64] u8 = [
        0x81, 0x97, 0x3F, 0xE4, 0x96, 0x50, 0x33, 0x0A, 0x30, 0x75, 0xF4, 0x4C, 0xE0, 0x1E, 0x80, 0x2F,
        0x07, 0xF9, 0x6E, 0xEE, 0x09, 0x02, 0xBD, 0x73, 0xB7, 0xA0, 0x39, 0x30, 0x33, 0xE8, 0x09, 0x61,
        0x1F, 0x72, 0xB8, 0x07, 0xAC, 0xB1, 0x7D, 0x05, 0x1E, 0x38, 0xE5, 0x67, 0xAE, 0xBF, 0xEF, 0x73,
        0x37, 0x14, 0xDA, 0x6E, 0xF4, 0x4E, 0xED, 0xA9, 0x65, 0x99, 0xA7, 0x78, 0xC7, 0x82, 0xD6, 0x17]
    Swag.require(Slice.equals(credential.toSlice(), Expected))
}

// Adding, replacing, and removing key files all keep exactly one verified access slot.
#test
{
    let oldKey = accessTestPath("old-key")
    defer discard catch File.delete(oldKey)
    let newKey = accessTestPath("new-key")
    defer discard catch File.delete(newKey)
    let vault = accessTestPath("vault")
    defer discard catch File.delete(vault)

    discard expect File.writeAllBytes(oldKey, [10'u8, 11, 12])
    discard expect File.writeAllBytes(newKey, [20'u8, 21, 22])

    var oldFiles: Array'String
    oldFiles.add(oldKey)
    var oldAccess: VaultAccess
    oldAccess.setInputs(accessTestPassword(), oldFiles.toSlice())
    var oldCredential = expect oldAccess.derive()

    var newFiles: Array'String
    newFiles.add(newKey)
    var newAccess: VaultAccess
    newAccess.setInputs(accessTestPassword(), newFiles.toSlice())
    var newCredential = expect newAccess.derive()

    var rawCredential: VaultCredential
    rawCredential.bytes.add(accessTestPassword())

    // Add the first key file to a password-only vault.
    var volume = expect Volume.create(vault, rawCredential.toSlice(), MinimumSize)
    expect volume.changePassword(rawCredential.toSlice(), oldCredential.toSlice())
    Swag.require(volume.keySlotCount() == 1)
    volume.close()

    var rawAfterAddErrorOutcome: Swag.Error
    discard catch Volume.open(vault, rawCredential.toSlice()) as rawAfterAddErrorOutcome
    let rawAfterAddError = rawAfterAddErrorOutcome.value()
    Swag.require(rawAfterAddError != null)
    volume = expect Volume.open(vault, oldCredential.toSlice())

    // Replace its key-file set.
    expect volume.changePassword(oldCredential.toSlice(), newCredential.toSlice())
    Swag.require(volume.keySlotCount() == 1)
    volume.close()

    var oldErrorOutcome: Swag.Error
    discard catch Volume.open(vault, oldCredential.toSlice()) as oldErrorOutcome
    let oldError = oldErrorOutcome.value()
    Swag.require(oldError != null)
    volume = expect Volume.open(vault, newCredential.toSlice())

    // Remove every key file while preserving the panel password.
    expect volume.changePassword(newCredential.toSlice(), rawCredential.toSlice())
    Swag.require(volume.keySlotCount() == 1)
    volume.close()

    var newAfterRemoveErrorOutcome: Swag.Error
    discard catch Volume.open(vault, newCredential.toSlice()) as newAfterRemoveErrorOutcome
    let newAfterRemoveError = newAfterRemoveErrorOutcome.value()
    Swag.require(newAfterRemoveError != null)
    var reopened = expect Volume.open(vault, rawCredential.toSlice())
    reopened.close()
}

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
    Swag.assert(Slice.equals(credential.toSlice(), accessTestPassword()))
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
    Swag.assert(Slice.equals(firstCredential.toSlice(), movedCredential.toSlice()))

    var reversedFiles: Array'String
    reversedFiles.add(secondPath)
    reversedFiles.add(firstPath)
    var reversed: VaultAccess
    reversed.setInputs(accessTestPassword(), reversedFiles.toSlice())
    var reversedCredential = expect reversed.derive()
    Swag.assert(not Slice.equals(firstCredential.toSlice(), reversedCredential.toSlice()))

    var otherPassword: VaultAccess
    otherPassword.setInputs("different", firstFiles.toSlice())
    var otherCredential = expect otherPassword.derive()
    Swag.assert(not Slice.equals(firstCredential.toSlice(), otherCredential.toSlice()))
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
    Swag.assert(volume.keySlotCount() == 1)
    volume.close()

    discard catch Volume.open(vault, rawCredential.toSlice()) as rawAfterAddError
    Swag.assert(rawAfterAddError != null)
    volume = expect Volume.open(vault, oldCredential.toSlice())

    // Replace its key-file set.
    expect volume.changePassword(oldCredential.toSlice(), newCredential.toSlice())
    Swag.assert(volume.keySlotCount() == 1)
    volume.close()

    discard catch Volume.open(vault, oldCredential.toSlice()) as oldError
    Swag.assert(oldError != null)
    volume = expect Volume.open(vault, newCredential.toSlice())

    // Remove every key file while preserving the panel password.
    expect volume.changePassword(newCredential.toSlice(), rawCredential.toSlice())
    Swag.assert(volume.keySlotCount() == 1)
    volume.close()

    discard catch Volume.open(vault, newCredential.toSlice()) as newAfterRemoveError
    Swag.assert(newAfterRemoveError != null)
    var reopened = expect Volume.open(vault, rawCredential.toSlice())
    reopened.close()
}

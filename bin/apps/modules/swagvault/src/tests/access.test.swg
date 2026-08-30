#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func accessTestPassword()->const [..] u8
{
    return @mkslice(cast(const [*] u8) @dataof("panel password"), 14)
}

func accessTestSame(left, right: const [..] u8)->bool
{
    return @countof(left) == @countof(right) and @memcmp(@dataof(left), @dataof(right), @countof(left)) == 0
}

func accessTestPath(tag: string)->String
{
    return Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("vault_access_%_%.bin", tag, Guid64.random()))
}

// Password-only access uses the password bytes directly.
#test
{
    var files:  Array'String
    var access: VaultAccess
    access.setInputs(accessTestPassword(), files.toSlice())

    var credential = expect access.derive()
    @assert(accessTestSame(credential.toSlice(), accessTestPassword()))
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

    discard expect File.writeAllBytes(firstPath.toString(), [1'u8, 2, 3, 4])
    discard expect File.writeAllBytes(movedPath.toString(), [1'u8, 2, 3, 4])
    discard expect File.writeAllBytes(secondPath.toString(), [5'u8, 6, 7])

    var firstFiles: Array'String
    firstFiles.add(String.from(firstPath))
    firstFiles.add(String.from(secondPath))
    var first: VaultAccess
    first.setInputs(accessTestPassword(), firstFiles.toSlice())
    var firstCredential = expect first.derive()

    var movedFiles: Array'String
    movedFiles.add(String.from(movedPath))
    movedFiles.add(String.from(secondPath))
    var moved: VaultAccess
    moved.setInputs(accessTestPassword(), movedFiles.toSlice())
    var movedCredential = expect moved.derive()
    @assert(accessTestSame(firstCredential.toSlice(), movedCredential.toSlice()))

    var reversedFiles: Array'String
    reversedFiles.add(String.from(secondPath))
    reversedFiles.add(String.from(firstPath))
    var reversed: VaultAccess
    reversed.setInputs(accessTestPassword(), reversedFiles.toSlice())
    var reversedCredential = expect reversed.derive()
    @assert(!accessTestSame(firstCredential.toSlice(), reversedCredential.toSlice()))

    var otherPassword: VaultAccess
    otherPassword.setInputs("different", firstFiles.toSlice())
    var otherCredential = expect otherPassword.derive()
    @assert(!accessTestSame(firstCredential.toSlice(), otherCredential.toSlice()))
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

    discard expect File.writeAllBytes(oldKey.toString(), [10'u8, 11, 12])
    discard expect File.writeAllBytes(newKey.toString(), [20'u8, 21, 22])

    var oldFiles: Array'String
    oldFiles.add(String.from(oldKey))
    var oldAccess: VaultAccess
    oldAccess.setInputs(accessTestPassword(), oldFiles.toSlice())
    var oldCredential = expect oldAccess.derive()

    var newFiles: Array'String
    newFiles.add(String.from(newKey))
    var newAccess: VaultAccess
    newAccess.setInputs(accessTestPassword(), newFiles.toSlice())
    var newCredential = expect newAccess.derive()

    var rawCredential: VaultCredential
    rawCredential.bytes.add(accessTestPassword())

    // Add the first key file to a password-only vault.
    var volume = expect Volume.create(vault.toString(), rawCredential.toSlice(), MinimumSize)
    expect volume.changePassword(rawCredential.toSlice(), oldCredential.toSlice())
    @assert(volume.keySlotCount() == 1)
    volume.close()

    discard catch Volume.open(vault.toString(), rawCredential.toSlice()) as rawAfterAddError
    @assert(rawAfterAddError != null)
    volume = expect Volume.open(vault.toString(), oldCredential.toSlice())

    // Replace its key-file set.
    expect volume.changePassword(oldCredential.toSlice(), newCredential.toSlice())
    @assert(volume.keySlotCount() == 1)
    volume.close()

    discard catch Volume.open(vault.toString(), oldCredential.toSlice()) as oldError
    @assert(oldError != null)
    volume = expect Volume.open(vault.toString(), newCredential.toSlice())

    // Remove every key file while preserving the panel password.
    expect volume.changePassword(newCredential.toSlice(), rawCredential.toSlice())
    @assert(volume.keySlotCount() == 1)
    volume.close()

    discard catch Volume.open(vault.toString(), newCredential.toSlice()) as newAfterRemoveError
    @assert(newAfterRemoveError != null)
    var reopened = expect Volume.open(vault.toString(), rawCredential.toSlice())
    reopened.close()
}

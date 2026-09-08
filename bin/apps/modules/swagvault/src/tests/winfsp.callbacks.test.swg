#global if WINDOWS and #command == Swag.CompilerCommand.Test
#global private

using Core

struct DirectoryCapture
{
    names: Array'String
    limit: u64     // Zero accepts every entry; a non-zero value models a full WinFsp buffer.
}

func captureDirectoryEntry(context: *void?, name: const [*] u8?, info: const *WinFsp.FileInfo)->u8
{
    discard info
    let capture = cast(*DirectoryCapture) context!
    if capture.limit and capture.names.count >= capture.limit do
        return 0
    capture.names.add(WinFsp.cString(name))
    return 1
}

func captured(capture: const *DirectoryCapture, name: string)->bool
{
    for value in capture.names where value[] == name do
        return true
    return false
}

func statusForError(kind: ErrorKind)->s32
{
    catch failWith("test error", kind) as err
    return WinFsp.statusFromError(err)
}

#test
{
    Swag.assert(WinFsp.statusBits(cast #bit (s32) 0x80070430'u32) == 0x80070430)
    Swag.assert(statusForError(.InvalidInput) == WinFsp.StatusInvalidParameter)
    Swag.assert(statusForError(.SparseContainer) == WinFsp.StatusInvalidParameter)
    Swag.assert(statusForError(.NotFound) == WinFsp.StatusObjectNameNotFound)
    Swag.assert(statusForError(.AlreadyExists) == WinFsp.StatusObjectNameCollision)
    Swag.assert(statusForError(.AccessDenied) == WinFsp.StatusAccessDenied)
    Swag.assert(statusForError(.NotDirectory) == WinFsp.StatusNotADirectory)
    Swag.assert(statusForError(.IsDirectory) == WinFsp.StatusFileIsDirectory)
    Swag.assert(statusForError(.DirectoryNotEmpty) == WinFsp.StatusDirectoryNotEmpty)
    Swag.assert(statusForError(.DiskFull) == WinFsp.StatusDiskFull)
    Swag.assert(statusForError(.Corrupted) == WinFsp.StatusIoDeviceError)
    Swag.assert(WinFsp.statusFromError(null, WinFsp.StatusAccessDenied) == WinFsp.StatusAccessDenied)
}

#test
{
    Swag.assert(WinFsp.volumeSerialNumber(0x0123_4567_89AB_CDEF) == 0x89AB_CDEF)

    let temp = Env.getSpecialDirectory(.Temp)
    let path = Path.combine(temp.toString(), Format.toString("vault_callbacks_%.bin", Guid64.random()))
    defer discard catch File.delete(path)

    let password = Swag.makeSlice(cast(const [*] u8) ("callback password").buffer, 17)
    var volume   = expect Volume.create(path, password, MinimumSize)
    let context  = cast(*void) &volume

    var total, free: u64
    var label:       [64] u8
    var callbackStatus = WinFsp.callbackGetVolumeInfo(context, &total, &free, &label[0], cast(u32) #sizeof(label))
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(total == volume.totalBytes())
    Swag.assert(free == volume.freeBytes())
    Swag.assert(WinFsp.cString(&label[0]) == "Swag Vault")
    callbackStatus = WinFsp.callbackSetVolumeLabel(context, ("Private").buffer)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)

    var directoryId, fileId, secondFileId, thirdFileId: u64
    var info: WinFsp.FileInfo
    let sequenceBeforeCreate = volume.sequence
    callbackStatus = WinFsp.callbackCreate(context, ("\\docs").buffer, 1, FileAttributeDirectory, 0, null, 0, &directoryId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(info.fileAttributes & FileAttributeDirectory)
    Swag.assert(volume.sequence == sequenceBeforeCreate and volume.hasPendingChanges())
    WinFsp.callbackCleanup(context, directoryId, 0)
    Swag.assert(volume.sequence == sequenceBeforeCreate + 1 and !volume.hasPendingChanges())

    let security: [4] u8 = [10, 20, 30, 40]
    callbackStatus = WinFsp.callbackCreate(context, ("\\docs\\data.bin").buffer, 0, FileAttributeNormal, 0, &security[0], #sizeof(security), &fileId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(info.indexNumber == fileId and info.fileSize == 0)
    callbackStatus = WinFsp.callbackCreate(context, ("\\docs\\second.bin").buffer, 0, FileAttributeNormal, 0, null, 0, &secondFileId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    callbackStatus = WinFsp.callbackCreate(context, ("\\docs\\third.bin").buffer, 0, FileAttributeNormal, 0, null, 0, &thirdFileId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)

    var lookupId: u64
    callbackStatus = WinFsp.callbackLookup(context, ("\\DOCS\\DATA.BIN").buffer, &lookupId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(lookupId == fileId)
    callbackStatus = WinFsp.callbackLookup(context, ("\\missing").buffer, &lookupId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusObjectNameNotFound)

    var source: [5000] u8
    for value, i in source do
        source[i] = cast(u8) ((i * 13 + 5) & 0xFF)
    var transferred: u32
    callbackStatus = WinFsp.callbackWrite(context, fileId, &source[0], 0, #sizeof(source), 0, 0, &transferred, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(transferred == #sizeof(source) and info.fileSize == #sizeof(source))
    callbackStatus = WinFsp.callbackFlush(context, fileId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)

    var destination: [5000] u8
    callbackStatus = WinFsp.callbackRead(context, fileId, &destination[0], 0, #sizeof(destination), &transferred)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(transferred == #sizeof(destination))
    Swag.assert(Swag.memcmp(&source[0], &destination[0], #sizeof(source)) == 0)

    callbackStatus = WinFsp.callbackSetFileSize(context, fileId, 9000, 0, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(info.fileSize == 9000)
    callbackStatus = WinFsp.callbackSetBasicInfo(context, fileId, FileAttributeArchive, 11, 12, 13, 14, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(info.creationTime == 11 and info.lastAccessTime == 12 and info.lastWriteTime == 13 and info.changeTime == 14)
    callbackStatus = WinFsp.callbackFlush(context, fileId, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)

    var zeroTail: [32] u8
    callbackStatus = WinFsp.callbackRead(context, fileId, &zeroTail[0], 7000, #sizeof(zeroTail), &transferred)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    for byte in zeroTail do
        Swag.assert(byte == 0)

    var securitySize = 0'u32
    callbackStatus = WinFsp.callbackGetSecurity(context, fileId, null, &securitySize)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(securitySize == #sizeof(security))
    var shortSecurity: [2] u8
    securitySize   = #sizeof(shortSecurity)
    callbackStatus = WinFsp.callbackGetSecurity(context, fileId, &shortSecurity[0], &securitySize)
    Swag.assert(callbackStatus == WinFsp.StatusBufferOverflow)
    var readSecurity: [4] u8
    securitySize   = #sizeof(readSecurity)
    callbackStatus = WinFsp.callbackGetSecurity(context, fileId, &readSecurity[0], &securitySize)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(Swag.memcmp(&security[0], &readSecurity[0], #sizeof(security)) == 0)

    let replacementSecurity: [3] u8 = [7, 8, 9]
    callbackStatus = WinFsp.callbackSetSecurity(context, fileId, &replacementSecurity[0], #sizeof(replacementSecurity))
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)

    var rootCapture: DirectoryCapture
    var complete:    u8
    callbackStatus = WinFsp.callbackReadDirectory(context, 1, null, &captureDirectoryEntry, &rootCapture, &complete)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(complete == 1 and captured(&rootCapture, "docs"))

    var childCapture: DirectoryCapture
    complete       = 0
    callbackStatus = WinFsp.callbackReadDirectory(context, directoryId, null, &captureDirectoryEntry, &childCapture, &complete)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(complete == 1 and captured(&childCapture, ".") and captured(&childCapture, "..") and captured(&childCapture, "data.bin"))
    callbackStatus = WinFsp.callbackGetDirInfoByName(context, directoryId, ("DATA.BIN").buffer, &info)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)

    var firstPage: DirectoryCapture
    firstPage.limit = 3
    complete        = 0
    callbackStatus  = WinFsp.callbackReadDirectory(context, directoryId, null, &captureDirectoryEntry, &firstPage, &complete)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(!complete and firstPage.names.count == 3 and firstPage.names[2] == "data.bin")

    var secondPage: DirectoryCapture
    complete       = 0
    callbackStatus = WinFsp.callbackReadDirectory(context, directoryId, ("data.bin").buffer, &captureDirectoryEntry, &secondPage, &complete)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    Swag.assert(complete and secondPage.names.count == 2 and secondPage.names[0] == "second.bin" and secondPage.names[1] == "third.bin")

    callbackStatus = WinFsp.callbackCanDelete(context, directoryId)
    Swag.assert(callbackStatus == WinFsp.StatusDirectoryNotEmpty)
    callbackStatus = WinFsp.callbackCanDelete(context, 1)
    Swag.assert(callbackStatus == WinFsp.StatusAccessDenied)
    callbackStatus = WinFsp.callbackRead(context, directoryId, &destination[0], 0, 1, &transferred)
    Swag.assert(callbackStatus == WinFsp.StatusFileIsDirectory)
    callbackStatus = WinFsp.callbackSetFileSize(context, directoryId, 1, 0, &info)
    Swag.assert(callbackStatus == WinFsp.StatusFileIsDirectory)
    callbackStatus = WinFsp.callbackReadDirectory(context, fileId, null, &captureDirectoryEntry, &childCapture, &complete)
    Swag.assert(callbackStatus == WinFsp.StatusNotADirectory)

    callbackStatus = WinFsp.callbackRename(context, fileId, ("\\docs\\data.bin").buffer, ("\\docs\\renamed.bin").buffer, 0)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    WinFsp.callbackCleanup(context, fileId, WinFsp.CleanupDelete)
    WinFsp.callbackCleanup(context, secondFileId, WinFsp.CleanupDelete)
    WinFsp.callbackCleanup(context, thirdFileId, WinFsp.CleanupDelete)
    callbackStatus = WinFsp.callbackCanDelete(context, directoryId)
    Swag.assert(callbackStatus == WinFsp.StatusSuccess)
    WinFsp.callbackCleanup(context, directoryId, WinFsp.CleanupDelete)
    volume.close()

    var reopened = expect Volume.open(path, password)
    Swag.assert(reopened.label == "Private")
    Swag.assert(reopened.resolve("\\docs") == null)
    reopened.close()
}

#test
{
    // No ordinary test run may reach the elevation path. An automated run has
    // nobody to accept a Windows consent dialog, so a test that regressed into
    // mounting would hang rather than fail. The guardian refuses outright in
    // this build, and the mounting harness is not even compiled into it.
    Swag.assert(!WinFsp.canRequestElevation())
    discard catch WinFsp.ensurePortableGuardian() as elevationRefused
    Swag.assert(elevationRefused != null)
}

#test
{
    let temp = Env.getSpecialDirectory(.Temp)
    let path = Path.combine(temp.toString(), Format.toString("vault_batch_rename_%.bin", Guid64.random()))
    defer discard catch File.delete(path)
    let password: const [..] u8 = cast() "batch rename password"
    let security: const [..] u8 = cast() ""
    var volume = expect Volume.create(path, password, MinimumSize)
    discard expect volume.createNode("\\vid1", true, FileAttributeDirectory, security)
    let occupied = expect volume.createNode("\\vid1\\clip (1).mp4", false, FileAttributeNormal, security)

    const FileCount = 12
    var ids: [FileCount] u64
    for i in FileCount
    {
        let source = Format.toString("\\vid1\\source-%.mp4", i)
        ids[i] = expect volume.createNode(source, false, FileAttributeNormal, security)
        let bytes: [1] u8 = [cast(u8) (i + 1)]
        let bytesWritten  = expect volume.writeNode(ids[i], 0, bytes, false, false)
        Swag.assert(bytesWritten == 1)
    }

    expect volume.commit()
    for i in FileCount
    {
        let source      = Format.toString("\\vid1\\source-%.mp4", i)
        let destination = Format.toString("\\vid1\\clip (%).mp4", i + 2)

        // WinFsp dispatchers do not inherit the main thread's initialized error allocator.
        let previous = Swag.getContext()
        defer Swag.setContext(previous)
        var context: Swag.Context
        context.allocator        = previous.allocator
        context.defaultAllocator = previous.defaultAllocator
        context.runtimeFlags     = previous.runtimeFlags
        Swag.setContext(context)
        defer context.errorAllocator.release()

        let callbackStatus = WinFsp.callbackRename(&volume, ids[i], source.buffer, ("\\vid1\\CLIP (1).MP4").buffer, 0)
        Swag.assert(callbackStatus == WinFsp.StatusObjectNameCollision)
        Swag.assert(volume.resolve(source)!.id == ids[i])
        Swag.assert(volume.resolve("\\vid1\\clip (1).mp4")!.id == occupied)
        let callbackStatus2 = WinFsp.callbackRename(&volume, ids[i], source.buffer, destination.buffer, 0)
        Swag.assert(callbackStatus2 == WinFsp.StatusSuccess)
        Swag.assert(volume.resolve(source) == null and volume.resolve(destination)!.id == ids[i])
        WinFsp.callbackCleanup(&volume, ids[i], 0)
    }

    volume.close()
    var reopened = expect Volume.open(path, password)
    for i in FileCount
    {
        let destination = Format.toString("\\vid1\\clip (%).mp4", i + 2)
        let node        = reopened.resolve(destination)
        Swag.assert(node != null and node!.id == ids[i])
        var bytes: [1] u8
        let bytesRead = expect reopened.readNode(ids[i], 0, bytes)
        Swag.assert(bytesRead == 1 and bytes[0] == i + 1)
    }
}

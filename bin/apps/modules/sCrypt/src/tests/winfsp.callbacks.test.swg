#global if WINDOWS and #command == Swag.CompilerCommand.Test
#global private

using Core

struct DirectoryCapture
{
    names: Array'String
    limit: u64     // Zero accepts every entry; a non-zero value models a full WinFsp buffer.
}

func captureDirectoryEntry(context: #null *void, name: #null const [*] u8, info: const *WinFsp.FileInfo)->u8
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
    for value in capture.names where dref value == name do
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
    @assert(WinFsp.statusBits(cast #bit (s32) 0x80070430'u32) == 0x80070430)
    @assert(statusForError(.InvalidInput) == WinFsp.StatusInvalidParameter)
    @assert(statusForError(.NotFound) == WinFsp.StatusObjectNameNotFound)
    @assert(statusForError(.AlreadyExists) == WinFsp.StatusObjectNameCollision)
    @assert(statusForError(.AccessDenied) == WinFsp.StatusAccessDenied)
    @assert(statusForError(.NotDirectory) == WinFsp.StatusNotADirectory)
    @assert(statusForError(.IsDirectory) == WinFsp.StatusFileIsDirectory)
    @assert(statusForError(.DirectoryNotEmpty) == WinFsp.StatusDirectoryNotEmpty)
    @assert(statusForError(.DiskFull) == WinFsp.StatusDiskFull)
    @assert(statusForError(.Corrupted) == WinFsp.StatusIoDeviceError)
    @assert(WinFsp.statusFromError(null, WinFsp.StatusAccessDenied) == WinFsp.StatusAccessDenied)
}

#test
{
    @assert(WinFsp.volumeSerialNumber(0x0123_4567_89AB_CDEF) == 0x89AB_CDEF)

    let temp = Env.getSpecialDirectory(.Temp)
    let path = Path.combine(temp.toString(), Format.toString("scrypt_callbacks_%.bin", Guid64.random()))
    defer discard catch File.delete(path)

    let password = @mkslice(cast(const [*] u8) @dataof("callback password"), 17)
    var volume   = expect Volume.create(path, password, MinimumSize)
    let context  = cast(*void) &volume

    var total, free: u64
    var label:       [64] u8
    @assert(WinFsp.callbackGetVolumeInfo(context, &total, &free, &label[0], cast(u32) #sizeof(label)) == WinFsp.StatusSuccess)
    @assert(total == volume.totalBytes())
    @assert(free == volume.freeBytes())
    @assert(WinFsp.cString(&label[0]) == "sCrypt")
    @assert(WinFsp.callbackSetVolumeLabel(context, @dataof("Private")) == WinFsp.StatusSuccess)

    var directoryId, fileId, secondFileId, thirdFileId: u64
    var info: WinFsp.FileInfo
    let sequenceBeforeCreate = volume.sequence
    @assert(WinFsp.callbackCreate(context, @dataof("\\docs"), 1, FileAttributeDirectory, 0, null, 0, &directoryId, &info) == WinFsp.StatusSuccess)
    @assert(info.fileAttributes & FileAttributeDirectory)
    @assert(volume.sequence == sequenceBeforeCreate and volume.hasPendingChanges())
    WinFsp.callbackCleanup(context, directoryId, 0)
    @assert(volume.sequence == sequenceBeforeCreate + 1 and !volume.hasPendingChanges())

    let security: [4] u8 = [10, 20, 30, 40]
    @assert(WinFsp.callbackCreate(context, @dataof("\\docs\\data.bin"), 0, FileAttributeNormal, 0, &security[0], #sizeof(security), &fileId, &info) == WinFsp.StatusSuccess)
    @assert(info.indexNumber == fileId and info.fileSize == 0)
    @assert(WinFsp.callbackCreate(context, @dataof("\\docs\\second.bin"), 0, FileAttributeNormal, 0, null, 0, &secondFileId, &info) == WinFsp.StatusSuccess)
    @assert(WinFsp.callbackCreate(context, @dataof("\\docs\\third.bin"), 0, FileAttributeNormal, 0, null, 0, &thirdFileId, &info) == WinFsp.StatusSuccess)

    var lookupId: u64
    @assert(WinFsp.callbackLookup(context, @dataof("\\DOCS\\DATA.BIN"), &lookupId, &info) == WinFsp.StatusSuccess)
    @assert(lookupId == fileId)
    @assert(WinFsp.callbackLookup(context, @dataof("\\missing"), &lookupId, &info) == WinFsp.StatusObjectNameNotFound)

    var source: [5000] u8
    for value, i in source do
        source[i] = cast(u8) ((i * 13 + 5) & 0xFF)
    var transferred: u32
    @assert(WinFsp.callbackWrite(context, fileId, &source[0], 0, #sizeof(source), 0, 0, &transferred, &info) == WinFsp.StatusSuccess)
    @assert(transferred == #sizeof(source) and info.fileSize == #sizeof(source))
    @assert(WinFsp.callbackFlush(context, fileId, &info) == WinFsp.StatusSuccess)

    var destination: [5000] u8
    @assert(WinFsp.callbackRead(context, fileId, &destination[0], 0, #sizeof(destination), &transferred) == WinFsp.StatusSuccess)
    @assert(transferred == #sizeof(destination))
    @assert(@memcmp(&source[0], &destination[0], #sizeof(source)) == 0)

    @assert(WinFsp.callbackSetFileSize(context, fileId, 9000, 0, &info) == WinFsp.StatusSuccess)
    @assert(info.fileSize == 9000)
    @assert(WinFsp.callbackSetBasicInfo(context, fileId, FileAttributeArchive, 11, 12, 13, 14, &info) == WinFsp.StatusSuccess)
    @assert(info.creationTime == 11 and info.lastAccessTime == 12 and info.lastWriteTime == 13 and info.changeTime == 14)
    @assert(WinFsp.callbackFlush(context, fileId, &info) == WinFsp.StatusSuccess)

    var zeroTail: [32] u8
    @assert(WinFsp.callbackRead(context, fileId, &zeroTail[0], 7000, #sizeof(zeroTail), &transferred) == WinFsp.StatusSuccess)
    for byte in zeroTail do
        @assert(byte == 0)

    var securitySize = 0'u32
    @assert(WinFsp.callbackGetSecurity(context, fileId, null, &securitySize) == WinFsp.StatusSuccess)
    @assert(securitySize == #sizeof(security))
    var shortSecurity: [2] u8
    securitySize = #sizeof(shortSecurity)
    @assert(WinFsp.callbackGetSecurity(context, fileId, &shortSecurity[0], &securitySize) == WinFsp.StatusBufferOverflow)
    var readSecurity: [4] u8
    securitySize = #sizeof(readSecurity)
    @assert(WinFsp.callbackGetSecurity(context, fileId, &readSecurity[0], &securitySize) == WinFsp.StatusSuccess)
    @assert(@memcmp(&security[0], &readSecurity[0], #sizeof(security)) == 0)

    let replacementSecurity: [3] u8 = [7, 8, 9]
    @assert(WinFsp.callbackSetSecurity(context, fileId, &replacementSecurity[0], #sizeof(replacementSecurity)) == WinFsp.StatusSuccess)

    var rootCapture: DirectoryCapture
    var complete:    u8
    @assert(WinFsp.callbackReadDirectory(context, 1, null, &captureDirectoryEntry, &rootCapture, &complete) == WinFsp.StatusSuccess)
    @assert(complete == 1 and captured(&rootCapture, "docs"))

    var childCapture: DirectoryCapture
    complete = 0
    @assert(WinFsp.callbackReadDirectory(context, directoryId, null, &captureDirectoryEntry, &childCapture, &complete) == WinFsp.StatusSuccess)
    @assert(complete == 1 and captured(&childCapture, ".") and captured(&childCapture, "..") and captured(&childCapture, "data.bin"))
    @assert(WinFsp.callbackGetDirInfoByName(context, directoryId, @dataof("DATA.BIN"), &info) == WinFsp.StatusSuccess)

    var firstPage: DirectoryCapture
    firstPage.limit = 3
    complete        = 0
    @assert(WinFsp.callbackReadDirectory(context, directoryId, null, &captureDirectoryEntry, &firstPage, &complete) == WinFsp.StatusSuccess)
    @assert(!complete and firstPage.names.count == 3 and firstPage.names[2] == "data.bin")

    var secondPage: DirectoryCapture
    complete = 0
    @assert(WinFsp.callbackReadDirectory(context, directoryId, @dataof("data.bin"), &captureDirectoryEntry, &secondPage, &complete) == WinFsp.StatusSuccess)
    @assert(complete and secondPage.names.count == 2 and secondPage.names[0] == "second.bin" and secondPage.names[1] == "third.bin")

    @assert(WinFsp.callbackCanDelete(context, directoryId) == WinFsp.StatusDirectoryNotEmpty)
    @assert(WinFsp.callbackCanDelete(context, 1) == WinFsp.StatusAccessDenied)
    @assert(WinFsp.callbackRead(context, directoryId, &destination[0], 0, 1, &transferred) == WinFsp.StatusFileIsDirectory)
    @assert(WinFsp.callbackSetFileSize(context, directoryId, 1, 0, &info) == WinFsp.StatusFileIsDirectory)
    @assert(WinFsp.callbackReadDirectory(context, fileId, null, &captureDirectoryEntry, &childCapture, &complete) == WinFsp.StatusNotADirectory)

    @assert(WinFsp.callbackRename(context, fileId, @dataof("\\docs\\data.bin"), @dataof("\\docs\\renamed.bin"), 0) == WinFsp.StatusSuccess)
    WinFsp.callbackCleanup(context, fileId, WinFsp.CleanupDelete)
    WinFsp.callbackCleanup(context, secondFileId, WinFsp.CleanupDelete)
    WinFsp.callbackCleanup(context, thirdFileId, WinFsp.CleanupDelete)
    @assert(WinFsp.callbackCanDelete(context, directoryId) == WinFsp.StatusSuccess)
    WinFsp.callbackCleanup(context, directoryId, WinFsp.CleanupDelete)
    volume.close()

    var reopened = expect Volume.open(path, password)
    @assert(reopened.label == "Private")
    @assert(reopened.resolve("\\docs") == null)
    reopened.close()
}

#test
{
    // No ordinary test run may reach the elevation path. An automated run has
    // nobody to accept a Windows consent dialog, so a test that regressed into
    // mounting would hang rather than fail. The guardian refuses outright in
    // this build, and the mounting harness is not even compiled into it.
    @assert(!WinFsp.canRequestElevation())
    discard catch WinFsp.ensurePortableGuardian() as elevationRefused
    @assert(elevationRefused != null)
}

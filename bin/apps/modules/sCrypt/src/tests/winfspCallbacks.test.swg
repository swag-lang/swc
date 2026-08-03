#global if WINDOWS and #command == Swag.CompilerCommand.Test
#global private

using Core

struct DirectoryCapture
{
    names: Array'String
}

func captureDirectoryEntry(context: #null *void, name: #null const [*] u8,
                           info: const *SCrypt.Platform.FileInfo)->u8
{
    discard info
    let capture = cast(*DirectoryCapture) notnull context
    capture.names.add(SCrypt.Platform.cString(name))
    return 1
}

func captured(capture: const *DirectoryCapture, name: string)->bool
{
    for value in capture.names where value == name do
        return true
    return false
}

#test
{
    @assert(SCrypt.Platform.volumeSerialNumber(0x0123_4567_89AB_CDEF) == 0x89AB_CDEF)

    let temp = Env.getSpecialDirectory(.Temp)
    let path = Path.combine(temp.toString(),
        Format.toString("scrypt_callbacks_%.bin", Guid64.random()))
    defer discard catch File.delete(path)

    let password = @mkslice(cast(const [*] u8) @dataof("callback password"), 17)
    var volume = expect SCrypt.Volume.create(path, password, SCrypt.MinimumSize)
    let context = cast(*void) &volume

    var total, free: u64
    var label: [64] u8
    @assert(SCrypt.Platform.callbackGetVolumeInfo(context, &total, &free,
        &label[0], cast(u32) #sizeof(label)) == SCrypt.StatusSuccess)
    @assert(total == volume.totalBytes())
    @assert(free == volume.freeBytes())
    @assert(SCrypt.Platform.cString(&label[0]) == "sCrypt")
    @assert(SCrypt.Platform.callbackSetVolumeLabel(context, @dataof("Private")) ==
            SCrypt.StatusSuccess)

    var directoryId, fileId: u64
    var info: SCrypt.Platform.FileInfo
    @assert(SCrypt.Platform.callbackCreate(context, @dataof("\\docs"), 1,
        SCrypt.FileAttributeDirectory, 0, null, 0, &directoryId, &info) == SCrypt.StatusSuccess)
    @assert(info.fileAttributes & SCrypt.FileAttributeDirectory)

    let security: [4] u8 = [10, 20, 30, 40]
    @assert(SCrypt.Platform.callbackCreate(context, @dataof("\\docs\\data.bin"), 0,
        SCrypt.FileAttributeNormal, 0, &security[0], #sizeof(security), &fileId, &info) ==
        SCrypt.StatusSuccess)
    @assert(info.indexNumber == fileId and info.fileSize == 0)

    var lookupId: u64
    @assert(SCrypt.Platform.callbackLookup(context, @dataof("\\DOCS\\DATA.BIN"),
        &lookupId, &info) == SCrypt.StatusSuccess)
    @assert(lookupId == fileId)
    @assert(SCrypt.Platform.callbackLookup(context, @dataof("\\missing"),
        &lookupId, &info) == SCrypt.StatusObjectNameNotFound)

    var source: [5000] u8
    for value, [i] in source do source[i] = cast(u8) ((i * 13 + 5) & 0xFF)
    var transferred: u32
    @assert(SCrypt.Platform.callbackWrite(context, fileId, &source[0], 0, #sizeof(source),
        0, 0, &transferred, &info) == SCrypt.StatusSuccess)
    @assert(transferred == #sizeof(source) and info.fileSize == #sizeof(source))
    @assert(SCrypt.Platform.callbackFlush(context, fileId, &info) == SCrypt.StatusSuccess)

    var destination: [5000] u8
    @assert(SCrypt.Platform.callbackRead(context, fileId, &destination[0], 0,
        #sizeof(destination), &transferred) == SCrypt.StatusSuccess)
    @assert(transferred == #sizeof(destination))
    @assert(@memcmp(&source[0], &destination[0], #sizeof(source)) == 0)

    @assert(SCrypt.Platform.callbackSetFileSize(context, fileId, 9000, 0, &info) ==
            SCrypt.StatusSuccess)
    @assert(info.fileSize == 9000)
    @assert(SCrypt.Platform.callbackSetBasicInfo(context, fileId,
        SCrypt.FileAttributeArchive, 11, 12, 13, 14, &info) == SCrypt.StatusSuccess)
    @assert(info.creationTime == 11 and info.lastAccessTime == 12 and
            info.lastWriteTime == 13 and info.changeTime == 14)
    @assert(SCrypt.Platform.callbackFlush(context, fileId, &info) == SCrypt.StatusSuccess)

    var zeroTail: [32] u8
    @assert(SCrypt.Platform.callbackRead(context, fileId, &zeroTail[0], 7000,
        #sizeof(zeroTail), &transferred) == SCrypt.StatusSuccess)
    for byte in zeroTail do @assert(byte == 0)

    var securitySize = 0'u32
    @assert(SCrypt.Platform.callbackGetSecurity(context, fileId, null, &securitySize) ==
            SCrypt.StatusSuccess)
    @assert(securitySize == #sizeof(security))
    var shortSecurity: [2] u8
    securitySize = #sizeof(shortSecurity)
    @assert(SCrypt.Platform.callbackGetSecurity(context, fileId, &shortSecurity[0],
        &securitySize) == SCrypt.StatusBufferOverflow)
    var readSecurity: [4] u8
    securitySize = #sizeof(readSecurity)
    @assert(SCrypt.Platform.callbackGetSecurity(context, fileId, &readSecurity[0],
        &securitySize) == SCrypt.StatusSuccess)
    @assert(@memcmp(&security[0], &readSecurity[0], #sizeof(security)) == 0)

    let replacementSecurity: [3] u8 = [7, 8, 9]
    @assert(SCrypt.Platform.callbackSetSecurity(context, fileId,
        &replacementSecurity[0], #sizeof(replacementSecurity)) == SCrypt.StatusSuccess)

    var rootCapture: DirectoryCapture
    var complete: u8
    @assert(SCrypt.Platform.callbackReadDirectory(context, 1, null, &captureDirectoryEntry,
        &rootCapture, &complete) == SCrypt.StatusSuccess)
    @assert(complete == 1 and captured(&rootCapture, "docs"))

    var childCapture: DirectoryCapture
    complete = 0
    @assert(SCrypt.Platform.callbackReadDirectory(context, directoryId, null,
        &captureDirectoryEntry, &childCapture, &complete) == SCrypt.StatusSuccess)
    @assert(complete == 1 and captured(&childCapture, ".") and
            captured(&childCapture, "..") and captured(&childCapture, "data.bin"))
    @assert(SCrypt.Platform.callbackGetDirInfoByName(context, directoryId,
        @dataof("DATA.BIN"), &info) == SCrypt.StatusSuccess)

    @assert(SCrypt.Platform.callbackCanDelete(context, directoryId) ==
            SCrypt.StatusDirectoryNotEmpty)
    @assert(SCrypt.Platform.callbackCanDelete(context, 1) == SCrypt.StatusAccessDenied)
    @assert(SCrypt.Platform.callbackRead(context, directoryId, &destination[0], 0, 1,
        &transferred) == SCrypt.StatusFileIsDirectory)
    @assert(SCrypt.Platform.callbackSetFileSize(context, directoryId, 1, 0, &info) ==
            SCrypt.StatusFileIsDirectory)
    @assert(SCrypt.Platform.callbackReadDirectory(context, fileId, null,
        &captureDirectoryEntry, &childCapture, &complete) == SCrypt.StatusNotADirectory)

    @assert(SCrypt.Platform.callbackRename(context, fileId, @dataof("\\docs\\data.bin"),
        @dataof("\\docs\\renamed.bin"), 0) == SCrypt.StatusSuccess)
    SCrypt.Platform.callbackCleanup(context, fileId, SCrypt.CleanupDelete)
    @assert(SCrypt.Platform.callbackCanDelete(context, directoryId) == SCrypt.StatusSuccess)
    SCrypt.Platform.callbackCleanup(context, directoryId, SCrypt.CleanupDelete)
    volume.close()

    var reopened = expect SCrypt.Volume.open(path, password)
    @assert(reopened.label == "Private")
    @assert(reopened.resolve("\\docs") == null)
    reopened.close()
}

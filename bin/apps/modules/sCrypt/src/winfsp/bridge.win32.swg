#global if WINDOWS

using Core

namespace WinFsp
{
    struct NativeMountContext
    {
        volume:          *Volume = undefined
        defaultSecurity: #null *void
    }

    struct FspEmitContext
    {
        buffer:      #null *void
        length:      u32
        transferred: *u32 = undefined
    }

    func mountContext(fileSystem: *FspFileSystem)->*NativeMountContext
        => cast(*NativeMountContext) fileSystem.userContext!

    func mountedVolume(fileSystem: *FspFileSystem)->*Volume
        => mountContext(fileSystem).volume

    func idFromContext(context: #null *void)->u64 => cast(u64) context
    func contextFromId(nodeId: u64)->#null *void  => cast(#null *void) nodeId

    func stringFromWide(value: #null [*] u16)->String
    {
        if !value do
            return ""
        let validValue = value!
        return Utf8.fromUtf16(@mkslice(validValue, Utf16.lengthZeroTerminated(validValue)))
    }

    func copySecurity(fileSystem: *FspFileSystem, nodeId: u64, security: #null *void, securitySize: *u64)->s32
    {
        let context = mountContext(fileSystem)
        context.volume.accessLock.lockShared()
        defer context.volume.accessLock.unlockShared()
        let node    = context.volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound

        let available = dref securitySize
        let stored    = node!.security.toSlice()
        if @countof(stored)
        {
            dref securitySize = @countof(stored)
            if security and available < @countof(stored) do
                return StatusBufferOverflow
            if security do
                @memcpy(security!, @dataof(stored), @countof(stored))
            return StatusSuccess
        }

        let required = cast(u64) GetSecurityDescriptorLength(context.defaultSecurity)
        dref securitySize = required
        if security and available < required do
            return StatusBufferOverflow
        if security and required do
            @memcpy(security!, context.defaultSecurity!, required)
        return StatusSuccess
    }

    func fspGetVolumeInfo(fileSystem: *FspFileSystem, info: *FspVolumeInfo)->s32
    {
        var label: [128] u8
        let status = callbackGetVolumeInfo(mountedVolume(fileSystem), &info.totalSize, &info.freeSize, @dataof(label), cast(u32) @countof(label))
        if status != StatusSuccess do
            return status

        let label16 = Utf16.fromUtf8(cString(@dataof(label)))
        let count   = Math.min(@countof(label16), cast(u64) @countof(info.volumeLabel))
        if count do
            @memcpy(@dataof(info.volumeLabel), @dataof(label16), count * #sizeof(u16))
        info.volumeLabelLength = cast(u16) (count * #sizeof(u16))
        return StatusSuccess
    }

    func fspSetVolumeLabel(fileSystem: *FspFileSystem, label: #null [*] u16, info: *FspVolumeInfo)->s32
    {
        let value  = stringFromWide(label)
        let status = callbackSetVolumeLabel(mountedVolume(fileSystem), value.buffer)
        return status == StatusSuccess ? fspGetVolumeInfo(fileSystem, info) : status
    }

    func fspGetSecurityByName(fileSystem: *FspFileSystem, path: #null [*] u16, attributes: #null *u32, security: #null *void, securitySize: #null *u64)->s32
    {
        let value  = stringFromWide(path)
        var nodeId: u64
        var info:   FileInfo
        let status = callbackLookup(mountedVolume(fileSystem), value.buffer, &nodeId, &info)
        if status != StatusSuccess do
            return status
        if attributes do
            dref attributes = info.fileAttributes
        return securitySize ? copySecurity(fileSystem, nodeId, security, securitySize!) : StatusSuccess
    }

    func fspCreate(fileSystem: *FspFileSystem, path: #null [*] u16, createOptions, grantedAccess, attributes: u32, security: #null *void, allocationSize: u64, fileContext: *#null *void, info: *FileInfo)->s32
    {
        discard grantedAccess
        let value        = stringFromWide(path)
        let mounted      = mountedVolume(fileSystem)
        let directory    = cast(u8) ((createOptions & 1) != 0 ? 1 : 0)
        let securitySize = security ? GetSecurityDescriptorLength(security) : 0
        var nodeId: u64
        let status       = callbackCreate(mounted, value.buffer, directory, attributes, allocationSize, security, securitySize, &nodeId, info)
        if status == StatusSuccess do
            dref fileContext = contextFromId(nodeId)
        return status
    }

    func fspOpen(fileSystem: *FspFileSystem, path: #null [*] u16, createOptions, grantedAccess: u32, fileContext: *#null *void, info: *FileInfo)->s32
    {
        discard createOptions
        discard grantedAccess
        let value  = stringFromWide(path)
        var nodeId: u64
        let status = callbackLookup(mountedVolume(fileSystem), value.buffer, &nodeId, info)
        if status == StatusSuccess do
            dref fileContext = contextFromId(nodeId)
        return status
    }

    func fspOverwrite(fileSystem: *FspFileSystem, fileContext: #null *void, attributes: u32, replaceAttributes: u8, allocationSize: u64, info: *FileInfo)->s32
        => callbackOverwrite(mountedVolume(fileSystem), idFromContext(fileContext), attributes, replaceAttributes, allocationSize, info)

    func fspCleanup(fileSystem: *FspFileSystem, fileContext: #null *void, path: #null [*] u16, flags: u32)
    {
        discard path
        callbackCleanup(mountedVolume(fileSystem), idFromContext(fileContext), flags)
    }

    func fspClose(fileSystem: *FspFileSystem, fileContext: #null *void)
    {
        discard fileSystem
        discard fileContext
    }

    func fspRead(fileSystem: *FspFileSystem, fileContext: #null *void, buffer: #null *void, offset: u64, length: u32, transferred: *u32)->s32
    {
        return callbackRead(mountedVolume(fileSystem), idFromContext(fileContext), buffer, offset, length, transferred)
    }

    func fspWrite(fileSystem: *FspFileSystem, fileContext: #null *void, buffer: #null *void, offset: u64, length: u32, writeToEnd, constrained: u8, transferred: *u32, info: *FileInfo)->s32
    {
        return callbackWrite(mountedVolume(fileSystem), idFromContext(fileContext), buffer, offset, length, writeToEnd, constrained, transferred, info)
    }

    func fspFlush(fileSystem: *FspFileSystem, fileContext: #null *void, info: #null *FileInfo)->s32
    {
        var scratch: FileInfo
        return callbackFlush(mountedVolume(fileSystem), idFromContext(fileContext), info ? info! : &scratch)
    }

    func fspGetFileInfo(fileSystem: *FspFileSystem, fileContext: #null *void, info: *FileInfo)->s32
    {
        return callbackGetFileInfo(mountedVolume(fileSystem), idFromContext(fileContext), info)
    }

    func fspSetBasicInfo(fileSystem: *FspFileSystem, fileContext: #null *void, attributes: u32, creationTime, lastAccessTime, lastWriteTime, changeTime: u64, info: *FileInfo)->s32
        => callbackSetBasicInfo(mountedVolume(fileSystem), idFromContext(fileContext), attributes, creationTime, lastAccessTime, lastWriteTime, changeTime, info)

    func fspSetFileSize(fileSystem: *FspFileSystem, fileContext: #null *void, newSize: u64, setAllocationSize: u8, info: *FileInfo)->s32
        => callbackSetFileSize(mountedVolume(fileSystem), idFromContext(fileContext), newSize, setAllocationSize, info)

    func fspCanDelete(fileSystem: *FspFileSystem, fileContext: #null *void, path: #null [*] u16)->s32
    {
        discard path
        return callbackCanDelete(mountedVolume(fileSystem), idFromContext(fileContext))
    }

    func fspRename(fileSystem: *FspFileSystem, fileContext: #null *void, oldPath, newPath: #null [*] u16, replace: u8)->s32
    {
        let oldValue = stringFromWide(oldPath)
        let newValue = stringFromWide(newPath)
        return callbackRename(mountedVolume(fileSystem), idFromContext(fileContext), oldValue.buffer, newValue.buffer, replace)
    }

    func fspGetSecurity(fileSystem: *FspFileSystem, fileContext: #null *void, security: #null *void, securitySize: *u64)->s32
        => copySecurity(fileSystem, idFromContext(fileContext), security, securitySize)

    func fspSetSecurity(fileSystem: *FspFileSystem, fileContext: #null *void, information: u32, modification: #null *void)->s32
    {
        let context = mountContext(fileSystem)
        let nodeId  = idFromContext(fileContext)
        var stored: Array'u8
        {
            context.volume.accessLock.lockShared()
            defer context.volume.accessLock.unlockShared()
            let node = context.volume.nodeById(nodeId)
            if !node do
                return StatusObjectNameNotFound
            stored.add(node!.security.toSlice())
        }

        let input = stored.count ? cast(#null const *void) stored.buffer : context.defaultSecurity
        var updated: #null *void
        let status = (g_WinFsp.setSecurityDescriptor)(input, information, modification, &updated)
        if status != StatusSuccess do
            return status

        let size   = GetSecurityDescriptorLength(updated)
        let result = callbackSetSecurity(context.volume, nodeId, updated, size)
        (g_WinFsp.deleteSecurityDescriptor)(updated, g_WinFsp.setSecurityAddress)
        return result
    }

    func emitFspDir(emitContext: #null *void, name: #null const [*] u8, info: const *FileInfo)->u8
    {
        let context = cast(*FspEmitContext) emitContext!
        let name16  = Utf16.toZeroTerminated(cString(name))
        let bytes   = #offsetof(FspDirInfo.fileName) + @countof(name16) * #sizeof(u16)
        if bytes > Swag.U16.Max do
            return 0

        var storage: Array'u8
        storage.resize(bytes)
        @memset(storage.buffer, 0, bytes)
        let dirInfo = cast(*FspDirInfo) storage.buffer!
        dirInfo.size     = cast(u16) bytes
        dirInfo.fileInfo = dref info
        if @countof(name16) > 1 do
            @memcpy(&dirInfo.fileName[0], @dataof(name16), (@countof(name16) - 1) * #sizeof(u16))
        return (g_WinFsp.addDirInfo)(dirInfo, context.buffer, context.length, context.transferred)
    }

    func fspReadDirectory(fileSystem: *FspFileSystem, fileContext: #null *void, pattern, marker: #null [*] u16, buffer: #null *void, length: u32, transferred: *u32)->s32
    {
        discard pattern
        let markerValue = stringFromWide(marker)
        var context     = FspEmitContext{buffer: buffer, length: length, transferred: transferred}
        var complete: u8
        let status      = callbackReadDirectory(mountedVolume(fileSystem), idFromContext(fileContext), markerValue.buffer, &emitFspDir, &context, &complete)
        if status == StatusSuccess and complete do
            discard (g_WinFsp.addDirInfo)(null, buffer, length, transferred)
        return status
    }

    func fspGetDirInfoByName(fileSystem: *FspFileSystem, fileContext: #null *void, name: #null [*] u16, dirInfo: *FspDirInfo)->s32
    {
        let value  = stringFromWide(name)
        var info: FileInfo
        let status = callbackGetDirInfoByName(mountedVolume(fileSystem), idFromContext(fileContext), value.buffer, &info)
        if status != StatusSuccess do
            return status

        let name16 = Utf16.toZeroTerminated(value)
        let bytes  = #offsetof(FspDirInfo.fileName) + @countof(name16) * #sizeof(u16)
        if bytes > Swag.U16.Max do
            return StatusInvalidParameter
        dirInfo.size     = cast(u16) bytes
        dirInfo.fileInfo = info
        if @countof(name16) > 1 do
            @memcpy(&dirInfo.fileName[0], @dataof(name16), (@countof(name16) - 1) * #sizeof(u16))
        return StatusSuccess
    }

    // Builds the dispatch table WinFsp calls for every filesystem request.
    //
    // Slots left null are operations WinFsp treats as unsupported, which is the
    // intended answer for the ones sCrypt does not implement.
    func makeInterface()->FspInterface
    {
        with var result: retval
        {
            .getVolumeInfo     = &fspGetVolumeInfo
            .setVolumeLabel    = &fspSetVolumeLabel
            .getSecurityByName = &fspGetSecurityByName
            .create            = &fspCreate
            .open              = &fspOpen
            .overwrite         = &fspOverwrite
            .cleanup           = &fspCleanup
            .close             = &fspClose
            .read              = &fspRead
            .write             = &fspWrite
            .flush             = &fspFlush
            .getFileInfo       = &fspGetFileInfo
            .setBasicInfo      = &fspSetBasicInfo
            .setFileSize       = &fspSetFileSize
            .canDelete         = &fspCanDelete
            .rename            = &fspRename
            .getSecurity       = &fspGetSecurity
            .setSecurity       = &fspSetSecurity
            .readDirectory     = &fspReadDirectory
            .getDirInfoByName  = &fspGetDirInfoByName
        }

        return result
    }

    var g_FspInterface:      FspInterface
    var g_FspInterfaceReady: bool
}

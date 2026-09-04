#global if WINDOWS

using Core

namespace WinFsp
{
    struct NativeMountContext
    {
        late volume:     *Volume
        defaultSecurity: *void?
    }

    struct FspEmitContext
    {
        buffer:      *void?
        length:      u32
        transferred: *u32
    }

    func mountContext(fileSystem: *FspFileSystem)->*NativeMountContext
        => cast(*NativeMountContext) fileSystem.userContext!

    func mountedVolume(fileSystem: *FspFileSystem)->*Volume
        => mountContext(fileSystem).volume

    func idFromContext(context: *void?)->u64 => cast(u64) context
    func contextFromId(nodeId: u64)->*void?  => cast(*void?) nodeId

    func stringFromWide(value: [*] u16?)->String
    {
        if !value do
            return ""
        let validValue = value!
        return Utf8.fromUtf16(Swag.makeSlice(validValue, Utf16.lengthZeroTerminated(validValue)))
    }

    func copySecurity(fileSystem: *FspFileSystem, nodeId: u64, security: *void?, securitySize: *u64)->s32
    {
        let context = mountContext(fileSystem)
        context.volume.accessLock.lockShared()
        defer context.volume.accessLock.unlockShared()
        let node = context.volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound

        let available = securitySize[]
        let stored    = node!.security.toSlice()
        if stored.count
        {
            securitySize[] = stored.count
            if security and available < stored.count do
                return StatusBufferOverflow
            if security do
                Swag.memcpy(security!, stored.buffer, stored.count)
            return StatusSuccess
        }

        let required = cast(u64) GetSecurityDescriptorLength(context.defaultSecurity)
        securitySize[] = required
        if security and available < required do
            return StatusBufferOverflow
        if security and required do
            Swag.memcpy(security!, context.defaultSecurity!, required)
        return StatusSuccess
    }

    func fspGetVolumeInfo(fileSystem: *FspFileSystem, info: *FspVolumeInfo)->s32
    {
        var label: [128] u8
        let status = callbackGetVolumeInfo(mountedVolume(fileSystem), &info.totalSize, &info.freeSize, label.buffer, cast(u32) label.count)
        if status != StatusSuccess do
            return status

        let label16 = Utf16.fromUtf8(cString(label.buffer))
        let count   = Math.min(label16.count, cast(u64) info.volumeLabel.count)
        if count do
            Swag.memcpy(info.volumeLabel.buffer, label16.buffer, count * #sizeof(u16))
        info.volumeLabelLength = cast(u16) (count * #sizeof(u16))
        return StatusSuccess
    }

    func fspSetVolumeLabel(fileSystem: *FspFileSystem, label: [*] u16?, info: *FspVolumeInfo)->s32
    {
        let value  = stringFromWide(label)
        let status = callbackSetVolumeLabel(mountedVolume(fileSystem), value.buffer)
        return status == StatusSuccess ? fspGetVolumeInfo(fileSystem, info) : status
    }

    func fspGetSecurityByName(fileSystem: *FspFileSystem, path: [*] u16?, attributes: *u32?, security: *void?, securitySize: *u64?)->s32
    {
        let value  = stringFromWide(path)
        var nodeId: u64
        var info:   FileInfo
        let status = callbackLookup(mountedVolume(fileSystem), value.buffer, &nodeId, &info)
        if status != StatusSuccess do
            return status
        if attributes do
            attributes[] = info.fileAttributes
        return securitySize ? copySecurity(fileSystem, nodeId, security, securitySize!) : StatusSuccess
    }

    func fspCreate(fileSystem: *FspFileSystem, path: [*] u16?, createOptions, grantedAccess, attributes: u32, security: *void?, allocationSize: u64, fileContext: *(*void?), info: *FileInfo)->s32
    {
        discard grantedAccess
        let value        = stringFromWide(path)
        let mounted      = mountedVolume(fileSystem)
        let directory    = cast(u8) ((createOptions & 1) != 0 ? 1 : 0)
        let securitySize = security ? GetSecurityDescriptorLength(security) : 0
        var nodeId: u64
        let status       = callbackCreate(mounted, value.buffer, directory, attributes, allocationSize, security, securitySize, &nodeId, info)
        if status == StatusSuccess do
            fileContext[] = contextFromId(nodeId)
        return status
    }

    func fspOpen(fileSystem: *FspFileSystem, path: [*] u16?, createOptions, grantedAccess: u32, fileContext: *(*void?), info: *FileInfo)->s32
    {
        discard createOptions
        discard grantedAccess
        let value  = stringFromWide(path)
        var nodeId: u64
        let status = callbackLookup(mountedVolume(fileSystem), value.buffer, &nodeId, info)
        if status == StatusSuccess do
            fileContext[] = contextFromId(nodeId)
        return status
    }

    func fspOverwrite(fileSystem: *FspFileSystem, fileContext: *void?, attributes: u32, replaceAttributes: u8, allocationSize: u64, info: *FileInfo)->s32
        => callbackOverwrite(mountedVolume(fileSystem), idFromContext(fileContext), attributes, replaceAttributes, allocationSize, info)

    func fspCleanup(fileSystem: *FspFileSystem, fileContext: *void?, path: [*] u16?, flags: u32)
    {
        discard path
        callbackCleanup(mountedVolume(fileSystem), idFromContext(fileContext), flags)
    }

    func fspClose(fileSystem: *FspFileSystem, fileContext: *void?)
    {
        discard fileSystem
        discard fileContext
    }

    func fspRead(fileSystem: *FspFileSystem, fileContext: *void?, buffer: *void?, offset: u64, length: u32, transferred: *u32)->s32
    {
        return callbackRead(mountedVolume(fileSystem), idFromContext(fileContext), buffer, offset, length, transferred)
    }

    func fspWrite(fileSystem: *FspFileSystem, fileContext: *void?, buffer: *void?, offset: u64, length: u32, writeToEnd, constrained: u8, transferred: *u32, info: *FileInfo)->s32
    {
        return callbackWrite(mountedVolume(fileSystem), idFromContext(fileContext), buffer, offset, length, writeToEnd, constrained, transferred, info)
    }

    func fspFlush(fileSystem: *FspFileSystem, fileContext: *void?, info: *FileInfo?)->s32
    {
        var scratch: FileInfo
        return callbackFlush(mountedVolume(fileSystem), idFromContext(fileContext), info ? info! : &scratch)
    }

    func fspGetFileInfo(fileSystem: *FspFileSystem, fileContext: *void?, info: *FileInfo)->s32
    {
        return callbackGetFileInfo(mountedVolume(fileSystem), idFromContext(fileContext), info)
    }

    func fspSetBasicInfo(fileSystem: *FspFileSystem, fileContext: *void?, attributes: u32, creationTime, lastAccessTime, lastWriteTime, changeTime: u64, info: *FileInfo)->s32
        => callbackSetBasicInfo(mountedVolume(fileSystem), idFromContext(fileContext), attributes, creationTime, lastAccessTime, lastWriteTime, changeTime, info)

    func fspSetFileSize(fileSystem: *FspFileSystem, fileContext: *void?, newSize: u64, setAllocationSize: u8, info: *FileInfo)->s32
        => callbackSetFileSize(mountedVolume(fileSystem), idFromContext(fileContext), newSize, setAllocationSize, info)

    func fspCanDelete(fileSystem: *FspFileSystem, fileContext: *void?, path: [*] u16?)->s32
    {
        discard path
        return callbackCanDelete(mountedVolume(fileSystem), idFromContext(fileContext))
    }

    func fspRename(fileSystem: *FspFileSystem, fileContext: *void?, oldPath, newPath: [*] u16?, replace: u8)->s32
    {
        let oldValue = stringFromWide(oldPath)
        let newValue = stringFromWide(newPath)
        return callbackRename(mountedVolume(fileSystem), idFromContext(fileContext), oldValue.buffer, newValue.buffer, replace)
    }

    func fspGetSecurity(fileSystem: *FspFileSystem, fileContext: *void?, security: *void?, securitySize: *u64)->s32
        => copySecurity(fileSystem, idFromContext(fileContext), security, securitySize)

    func fspSetSecurity(fileSystem: *FspFileSystem, fileContext: *void?, information: u32, modification: *void?)->s32
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

        let input  = stored.count ? cast(const *void?) stored.buffer : context.defaultSecurity
        var updated: *void?
        let status = (g_WinFsp.setSecurityDescriptor)(input, information, modification, &updated)
        if status != StatusSuccess do
            return status

        let size   = GetSecurityDescriptorLength(updated)
        let result = callbackSetSecurity(context.volume, nodeId, updated, size)
        (g_WinFsp.deleteSecurityDescriptor)(updated, g_WinFsp.setSecurityAddress)
        return result
    }

    func emitFspDir(emitContext: *void?, name: const [*] u8?, info: const *FileInfo)->u8
    {
        let context = cast(*FspEmitContext) emitContext!
        let name16  = Utf16.toZeroTerminated(cString(name))
        let bytes   = #offsetof(FspDirInfo.fileName) + name16.count * #sizeof(u16)
        if bytes > Swag.U16.Max do
            return 0

        var storage: Array'u8
        storage.resize(bytes)
        Swag.memset(storage.buffer, 0, bytes)
        let dirInfo = cast(*FspDirInfo) storage.buffer!
        dirInfo.size     = cast(u16) bytes
        dirInfo.fileInfo = info[]
        if name16.count > 1 do
            Swag.memcpy(&dirInfo.fileName[0], name16.buffer, (name16.count - 1) * #sizeof(u16))
        return (g_WinFsp.addDirInfo)(dirInfo, context.buffer, context.length, context.transferred)
    }

    func fspReadDirectory(fileSystem: *FspFileSystem, fileContext: *void?, pattern, marker: [*] u16?, buffer: *void?, length: u32, transferred: *u32)->s32
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

    func fspGetDirInfoByName(fileSystem: *FspFileSystem, fileContext: *void?, name: [*] u16?, dirInfo: *FspDirInfo)->s32
    {
        let value  = stringFromWide(name)
        var info: FileInfo
        let status = callbackGetDirInfoByName(mountedVolume(fileSystem), idFromContext(fileContext), value.buffer, &info)
        if status != StatusSuccess do
            return status

        let name16 = Utf16.toZeroTerminated(value)
        let bytes  = #offsetof(FspDirInfo.fileName) + name16.count * #sizeof(u16)
        if bytes > Swag.U16.Max do
            return StatusInvalidParameter
        dirInfo.size     = cast(u16) bytes
        dirInfo.fileInfo = info
        if name16.count > 1 do
            Swag.memcpy(&dirInfo.fileName[0], name16.buffer, (name16.count - 1) * #sizeof(u16))
        return StatusSuccess
    }

    // Builds the dispatch table WinFsp calls for every filesystem request.
    //
    // Slots left null are operations WinFsp treats as unsupported, which is the
    // intended answer for the ones Swag Vault does not implement.
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

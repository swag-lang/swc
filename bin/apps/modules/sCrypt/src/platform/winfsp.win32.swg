#global if WINDOWS

using Core

namespace SCrypt.Platform
{
    struct FileInfo
    {
        fileAttributes: u32
        reparseTag:     u32
        allocationSize: u64
        fileSize:       u64
        creationTime:   u64
        lastAccessTime: u64
        lastWriteTime:  u64
        changeTime:     u64
        indexNumber:    u64
        hardLinks:      u32
        eaSize:         u32
    }
    alias EmitDirFn = func(emitContext: #null *void, name: #null const [*] u8,
                            info: const *FileInfo)->u8

    func cString(value: #null const [*] u8)->string
    {
        if !value do
            return ""
        var length = 0'u64
        while value[length] do
            length += 1
        return @mkstring(value, length)
    }

    func volumeSerialNumber(creationTime: u64)->u32
        => cast(u32) (creationTime & 0xFFFF_FFFF)

    func fillInfo(volume: *SCrypt.Volume, nodeId: u64, output: *FileInfo)->s32
    {
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        let validNode = notnull node
        output.fileAttributes = validNode.attributes
        output.allocationSize = validNode.isDirectory() ? 0 :
                                (validNode.size + SCrypt.BlockSize - 1) / SCrypt.BlockSize * SCrypt.BlockSize
        output.fileSize       = validNode.size
        output.creationTime   = validNode.creationTime
        output.lastAccessTime = validNode.lastAccessTime
        output.lastWriteTime  = validNode.lastWriteTime
        output.changeTime     = validNode.changeTime
        output.indexNumber    = validNode.id
        return SCrypt.StatusSuccess
    }

    func callbackGetVolumeInfo(context: #null *void, total, free: *u64,
                               label: [*] u8, labelCapacity: u32)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        dref total = volume.totalBytes()
        dref free  = volume.freeBytes()
        let count = Math.min(volume.label.length, cast(u64) labelCapacity - 1)
        if count do
            @memcpy(label, volume.label.buffer, count)
        label[count] = 0
        return SCrypt.StatusSuccess
    }

    func callbackSetVolumeLabel(context: #null *void, label: #null const [*] u8)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let value = cString(label)
        if @countof(value) > 32 * 4 do
            return SCrypt.StatusInvalidParameter
        volume.label = value
        volume.dirty = true
        discard catch volume.commit() as err
        return err == null ? SCrypt.StatusSuccess : SCrypt.StatusIoDeviceError
    }

    func callbackLookup(context: #null *void, path: #null const [*] u8,
                        nodeId: *u64, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.resolve(cString(path))
        if !node do
            return SCrypt.StatusObjectNameNotFound
        dref nodeId = (notnull node).id
        return fillInfo(volume, dref nodeId, info)
    }

    func callbackCreate(context: #null *void, path: #null const [*] u8, directory: u8,
                        attributes: u32, allocationSize: u64, security: #null const *void,
                        securitySize: u32, nodeId: *u64, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let name = cString(path)
        if volume.resolve(name) do
            return SCrypt.StatusObjectNameCollision
        let parent = volume.resolveParent(name).parent
        if !parent do
            return SCrypt.StatusObjectNameNotFound
        var securityBytes = @mkslice(cast(const [*] u8) @dataof(""), 0)
        if securitySize do
            securityBytes = @mkslice(cast(const [*] u8) notnull security, securitySize)
        let id = catch volume.createNode(name, directory != 0, attributes, securityBytes) as err
        if err != null do
            return SCrypt.StatusIoDeviceError
        dref nodeId = id
        if !directory and allocationSize
        {
            discard catch volume.resizeNode(id, 0) as resizeErr
            if resizeErr != null do
                return SCrypt.StatusDiskFull
        }
        return fillInfo(volume, id, info)
    }

    func callbackOverwrite(context: #null *void, nodeId: u64, attributes: u32,
                           replaceAttributes: u8, allocationSize: u64, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        if (notnull node).isDirectory() do
            return SCrypt.StatusFileIsDirectory
        let validNode = notnull node
        volume.freeNodeBlocks(validNode)
        validNode.size = 0
        if replaceAttributes do
            validNode.attributes = attributes ? attributes : SCrypt.FileAttributeNormal
        else do
            validNode.attributes |= attributes
        validNode.changeTime = SCrypt.volumeTimeNow()
        validNode.lastWriteTime = validNode.changeTime
        volume.dirty = true
        discard catch volume.commit() as err
        return err == null ? fillInfo(volume, nodeId, info) : SCrypt.StatusIoDeviceError
    }

    func callbackCleanup(context: #null *void, nodeId: u64, flags: u32)
    {
        let volume = cast(*SCrypt.Volume) notnull context
        if (flags & SCrypt.CleanupDelete) != 0
        {
            discard catch volume.deleteNode(nodeId)
            return
        }
        let node = volume.nodeById(nodeId)
        if !node do
            return
        let now = SCrypt.volumeTimeNow()
        if (flags & SCrypt.CleanupSetArchiveBit) != 0 do
            node.attributes |= SCrypt.FileAttributeArchive
        if (flags & SCrypt.CleanupSetLastAccessTime) != 0 do
            node.lastAccessTime = now
        if (flags & SCrypt.CleanupSetLastWriteTime) != 0 do
            node.lastWriteTime = now
        if (flags & SCrypt.CleanupSetChangeTime) != 0 do
            node.changeTime = now
        if (flags & (SCrypt.CleanupSetAllocationSize | SCrypt.CleanupSetArchiveBit |
                     SCrypt.CleanupSetLastAccessTime | SCrypt.CleanupSetLastWriteTime |
                     SCrypt.CleanupSetChangeTime)) != 0
        {
            volume.dirty = true
            discard catch volume.commit()
        }
    }

    func callbackRead(context: #null *void, nodeId: u64, buffer: #null *void,
                      offset: u64, length: u32, transferred: *u32)->s32
    {
        if !length
        {
            dref transferred = 0
            return SCrypt.StatusSuccess
        }
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        if (notnull node).isDirectory() do
            return SCrypt.StatusFileIsDirectory
        let count = catch volume.readNode(nodeId, offset,
            @mkslice(cast([*] u8) notnull buffer, length)) as err
        if err != null do
            return SCrypt.StatusIoDeviceError
        dref transferred = count
        return SCrypt.StatusSuccess
    }

    func callbackWrite(context: #null *void, nodeId: u64, buffer: #null const *void,
                       offset: u64, length: u32, writeToEnd, constrained: u8,
                       transferred: *u32, info: *FileInfo)->s32
    {
        if !length
        {
            dref transferred = 0
            return callbackGetFileInfo(context, nodeId, info)
        }
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        let validNode = notnull node
        if validNode.isDirectory() do
            return SCrypt.StatusFileIsDirectory
        var writeOffset = writeToEnd ? validNode.size : offset
        var writeLength = cast(u64) length
        if constrained
        {
            if writeOffset >= validNode.size do
                writeLength = 0
            else do
                writeLength = Math.min(writeLength, validNode.size - writeOffset)
        }
        if writeLength
        {
            if writeOffset > Swag.U64.Max - writeLength do
                return SCrypt.StatusInvalidParameter
            let firstBlock = writeOffset / SCrypt.BlockSize
            let lastBlock = (writeOffset + writeLength - 1) / SCrypt.BlockSize
            var needed = lastBlock - firstBlock + 1
            if !constrained and writeOffset + writeLength > validNode.size and
               validNode.size % SCrypt.BlockSize != 0 and
               validNode.blockSearch(validNode.size / SCrypt.BlockSize).found do
                needed += 1
            if volume.freeBlockCount() < needed do
                return SCrypt.StatusDiskFull
        }
        let count = catch volume.writeNode(nodeId, offset,
            @mkslice(cast(const [*] u8) notnull buffer, length),
            writeToEnd != 0, constrained != 0) as err
        if err != null do
            return volume.freeBlockCount() ? SCrypt.StatusIoDeviceError : SCrypt.StatusDiskFull
        dref transferred = count
        return fillInfo(volume, nodeId, info)
    }

    func callbackFlush(context: #null *void, nodeId: u64, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        discard catch volume.commit() as err
        if err != null do
            return SCrypt.StatusIoDeviceError
        if nodeId do
            return fillInfo(volume, nodeId, info)
        return SCrypt.StatusSuccess
    }

    func callbackGetFileInfo(context: #null *void, nodeId: u64, info: *FileInfo)->s32
    {
        return fillInfo(cast(*SCrypt.Volume) notnull context, nodeId, info)
    }

    func callbackSetBasicInfo(context: #null *void, nodeId: u64, attributes: u32,
                              creationTime, lastAccessTime, lastWriteTime, changeTime: u64,
                              info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        let validNode = notnull node
        if attributes != Swag.U32.Max
        {
            validNode.attributes = attributes ? attributes : SCrypt.FileAttributeNormal
            if validNode.isDirectory() do
                validNode.attributes |= SCrypt.FileAttributeDirectory
            else do
                validNode.attributes &= ~SCrypt.FileAttributeDirectory
        }
        if creationTime do validNode.creationTime = creationTime
        if lastAccessTime do validNode.lastAccessTime = lastAccessTime
        if lastWriteTime do validNode.lastWriteTime = lastWriteTime
        if changeTime do validNode.changeTime = changeTime
        volume.dirty = true
        return fillInfo(volume, nodeId, info)
    }

    func callbackSetFileSize(context: #null *void, nodeId, newSize: u64,
                             setAllocationSize: u8, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        let validNode = notnull node
        if validNode.isDirectory() do
            return SCrypt.StatusFileIsDirectory
        let targetSize = setAllocationSize and newSize < validNode.size ? newSize :
                         setAllocationSize ? validNode.size : newSize
        if targetSize > validNode.size and validNode.size % SCrypt.BlockSize != 0 and
           validNode.blockSearch(validNode.size / SCrypt.BlockSize).found and
           !volume.freeBlockCount() do
            return SCrypt.StatusDiskFull
        discard catch volume.resizeNode(nodeId, targetSize) as err
        if err != null do
            return SCrypt.StatusIoDeviceError
        return fillInfo(volume, nodeId, info)
    }

    func callbackCanDelete(context: #null *void, nodeId: u64)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        if nodeId == 1 do
            return SCrypt.StatusAccessDenied
        let validNode = notnull node
        if (validNode.attributes & SCrypt.FileAttributeReadOnly) != 0 do
            return SCrypt.StatusAccessDenied
        if validNode.isDirectory() and volume.hasChildren(nodeId) do
            return SCrypt.StatusDirectoryNotEmpty
        return SCrypt.StatusSuccess
    }

    func callbackRename(context: #null *void, nodeId: u64,
                        oldPath, newPath: #null const [*] u8, replace: u8)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        discard oldPath
        discard catch volume.renameNode(nodeId, cString(newPath), replace != 0) as err
        return err == null ? SCrypt.StatusSuccess : SCrypt.StatusAccessDenied
    }

    func callbackGetSecurity(context: #null *void, nodeId: u64,
                             security: #null *void, securitySize: *u32)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        let stored = (notnull node).security.toSlice()
        let available = dref securitySize
        dref securitySize = cast(u32) @countof(stored)
        if !@countof(stored) do
            return SCrypt.StatusSuccess
        if !security or available < @countof(stored) do
            return security ? SCrypt.StatusBufferOverflow : SCrypt.StatusSuccess
        @memcpy(notnull security, @dataof(stored), @countof(stored))
        return SCrypt.StatusSuccess
    }

    func callbackSetSecurity(context: #null *void, nodeId: u64,
                             security: #null const *void, securitySize: u32)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let node = volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound
        let validNode = notnull node
        validNode.security.resize(securitySize)
        if securitySize do
            @memcpy(validNode.security.buffer, notnull security, securitySize)
        validNode.changeTime = SCrypt.volumeTimeNow()
        volume.dirty = true
        return SCrypt.StatusSuccess
    }

    func sameName(left: string, right: string)->bool
    {
        return Utf8.compare(@mkslice(@dataof(left), @countof(left)),
                            @mkslice(@dataof(right), @countof(right)), .UnicodeNoCase) == 0
    }

    func callbackReadDirectory(context: #null *void, nodeId: u64,
                               marker: #null const [*] u8, emit: EmitDirFn,
                               emitContext: #null *void, complete: *u8)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let directory = volume.nodeById(nodeId)
        if !directory do
            return SCrypt.StatusObjectNameNotFound
        if !(notnull directory).isDirectory() do
            return SCrypt.StatusNotADirectory

        let markerName = cString(marker)
        var afterMarker = !@countof(markerName)
        var info: FileInfo
        if nodeId != 1
        {
            if afterMarker
            {
                discard fillInfo(volume, nodeId, &info)
                if !emit(emitContext, @dataof("."), &info) do
                    return SCrypt.StatusSuccess
            }
            elif sameName(markerName, ".") do afterMarker = true

            let parentId = (notnull directory).parentId
            if afterMarker
            {
                discard fillInfo(volume, parentId, &info)
                if !emit(emitContext, @dataof(".."), &info) do
                    return SCrypt.StatusSuccess
            }
            elif sameName(markerName, "..") do afterMarker = true
        }

        for child in volume.nodes where child.parentId == nodeId and child.id != nodeId
        {
            if !afterMarker
            {
                if sameName(markerName, child.name) do afterMarker = true
                continue
            }
            discard fillInfo(volume, child.id, &info)
            if !emit(emitContext, child.name.buffer, &info) do
                return SCrypt.StatusSuccess
        }
        dref complete = 1
        return SCrypt.StatusSuccess
    }

    func callbackGetDirInfoByName(context: #null *void, directoryId: u64,
                                  name: #null const [*] u8, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        let directory = volume.nodeById(directoryId)
        if !directory do
            return SCrypt.StatusObjectNameNotFound
        let value = cString(name)
        if value == "." do return fillInfo(volume, directoryId, info)
        if value == ".." do return fillInfo(volume, (notnull directory).parentId, info)
        let child = volume.findChild(directoryId, value)
        return child ? fillInfo(volume, (notnull child).id, info) : SCrypt.StatusObjectNameNotFound
    }

    struct NativeMountContext
    {
        volume:          *SCrypt.Volume = undefined
        defaultSecurity: #null *void
    }

    struct FspEmitContext
    {
        buffer:      #null *void
        length:      u32
        transferred: *u32 = undefined
    }

    func mountContext(fileSystem: *FspFileSystem)->*NativeMountContext
        => cast(*NativeMountContext) notnull fileSystem.userContext

    func mountedVolume(fileSystem: *FspFileSystem)->*SCrypt.Volume
        => mountContext(fileSystem).volume

    func idFromContext(context: #null *void)->u64 => cast(u64) context
    func contextFromId(nodeId: u64)->#null *void => cast(#null *void) nodeId

    func stringFromWide(value: #null [*] u16)->String
    {
        if !value do
            return ""
        let validValue = notnull value
        return Utf8.fromUtf16(@mkslice(validValue, Utf16.lengthZeroTerminated(validValue)))
    }

    func copySecurity(fileSystem: *FspFileSystem, nodeId: u64,
                      security: #null *void, securitySize: *u64)->s32
    {
        let context = mountContext(fileSystem)
        let node = context.volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound

        let available = dref securitySize
        let stored = (notnull node).security.toSlice()
        if @countof(stored)
        {
            dref securitySize = @countof(stored)
            if security and available < @countof(stored) do
                return SCrypt.StatusBufferOverflow
            if security do
                @memcpy(notnull security, @dataof(stored), @countof(stored))
            return SCrypt.StatusSuccess
        }

        let required = cast(u64) GetSecurityDescriptorLength(context.defaultSecurity)
        dref securitySize = required
        if security and available < required do
            return SCrypt.StatusBufferOverflow
        if security and required do
            @memcpy(notnull security, notnull context.defaultSecurity, required)
        return SCrypt.StatusSuccess
    }

    func fspGetVolumeInfo(fileSystem: *FspFileSystem, info: *FspVolumeInfo)->s32
    {
        var label: [128] u8
        let status = callbackGetVolumeInfo(mountedVolume(fileSystem),
            &info.totalSize, &info.freeSize, @dataof(label), cast(u32) @countof(label))
        if status != SCrypt.StatusSuccess do
            return status

        let label16 = Utf16.fromUtf8(cString(@dataof(label)))
        let count = Math.min(@countof(label16), cast(u64) @countof(info.volumeLabel))
        if count do
            @memcpy(@dataof(info.volumeLabel), @dataof(label16), count * #sizeof(u16))
        info.volumeLabelLength = cast(u16) (count * #sizeof(u16))
        return SCrypt.StatusSuccess
    }

    func fspSetVolumeLabel(fileSystem: *FspFileSystem, label: #null [*] u16,
                           info: *FspVolumeInfo)->s32
    {
        let value = stringFromWide(label)
        let status = callbackSetVolumeLabel(mountedVolume(fileSystem), value.buffer)
        return status == SCrypt.StatusSuccess ? fspGetVolumeInfo(fileSystem, info) : status
    }

    func fspGetSecurityByName(fileSystem: *FspFileSystem, path: #null [*] u16,
                              attributes: #null *u32, security: #null *void,
                              securitySize: #null *u64)->s32
    {
        let value = stringFromWide(path)
        var nodeId: u64
        var info: FileInfo
        let status = callbackLookup(mountedVolume(fileSystem), value.buffer, &nodeId, &info)
        if status != SCrypt.StatusSuccess do
            return status
        if attributes do
            dref attributes = info.fileAttributes
        return securitySize ? copySecurity(fileSystem, nodeId, security, notnull securitySize) :
                              SCrypt.StatusSuccess
    }

    func fspCreate(fileSystem: *FspFileSystem, path: #null [*] u16,
                   createOptions, grantedAccess, attributes: u32, security: #null *void,
                   allocationSize: u64, fileContext: *#null *void, info: *FileInfo)->s32
    {
        discard grantedAccess
        let value = stringFromWide(path)
        let directory = cast(u8) ((createOptions & 1) != 0 ? 1 : 0)
        let securitySize = security ? GetSecurityDescriptorLength(security) : 0
        var nodeId: u64
        let status = callbackCreate(mountedVolume(fileSystem), value.buffer, directory, attributes,
            allocationSize, security, securitySize, &nodeId, info)
        if status == SCrypt.StatusSuccess do
            dref fileContext = contextFromId(nodeId)
        return status
    }

    func fspOpen(fileSystem: *FspFileSystem, path: #null [*] u16,
                 createOptions, grantedAccess: u32, fileContext: *#null *void,
                 info: *FileInfo)->s32
    {
        discard createOptions
        discard grantedAccess
        let value = stringFromWide(path)
        var nodeId: u64
        let status = callbackLookup(mountedVolume(fileSystem), value.buffer, &nodeId, info)
        if status == SCrypt.StatusSuccess do
            dref fileContext = contextFromId(nodeId)
        return status
    }

    func fspOverwrite(fileSystem: *FspFileSystem, fileContext: #null *void,
                      attributes: u32, replaceAttributes: u8, allocationSize: u64,
                      info: *FileInfo)->s32
        => callbackOverwrite(mountedVolume(fileSystem), idFromContext(fileContext), attributes,
                             replaceAttributes, allocationSize, info)

    func fspCleanup(fileSystem: *FspFileSystem, fileContext: #null *void,
                    path: #null [*] u16, flags: u32)
    {
        discard path
        callbackCleanup(mountedVolume(fileSystem), idFromContext(fileContext), flags)
    }

    func fspClose(fileSystem: *FspFileSystem, fileContext: #null *void)
    {
        discard fileSystem
        discard fileContext
    }

    func fspRead(fileSystem: *FspFileSystem, fileContext: #null *void,
                 buffer: #null *void, offset: u64, length: u32, transferred: *u32)->s32
    {
        return callbackRead(mountedVolume(fileSystem), idFromContext(fileContext), buffer,
                            offset, length, transferred)
    }

    func fspWrite(fileSystem: *FspFileSystem, fileContext: #null *void,
                  buffer: #null *void, offset: u64, length: u32, writeToEnd, constrained: u8,
                  transferred: *u32, info: *FileInfo)->s32
    {
        return callbackWrite(mountedVolume(fileSystem), idFromContext(fileContext), buffer,
                             offset, length, writeToEnd, constrained, transferred, info)
    }

    func fspFlush(fileSystem: *FspFileSystem, fileContext: #null *void,
                  info: #null *FileInfo)->s32
    {
        var scratch: FileInfo
        return callbackFlush(mountedVolume(fileSystem), idFromContext(fileContext),
            info ? notnull info : &scratch)
    }

    func fspGetFileInfo(fileSystem: *FspFileSystem, fileContext: #null *void,
                        info: *FileInfo)->s32
    {
        return callbackGetFileInfo(mountedVolume(fileSystem), idFromContext(fileContext), info)
    }

    func fspSetBasicInfo(fileSystem: *FspFileSystem, fileContext: #null *void,
                         attributes: u32, creationTime, lastAccessTime,
                         lastWriteTime, changeTime: u64, info: *FileInfo)->s32
        => callbackSetBasicInfo(mountedVolume(fileSystem), idFromContext(fileContext), attributes,
                                creationTime, lastAccessTime, lastWriteTime, changeTime, info)

    func fspSetFileSize(fileSystem: *FspFileSystem, fileContext: #null *void,
                        newSize: u64, setAllocationSize: u8, info: *FileInfo)->s32
        => callbackSetFileSize(mountedVolume(fileSystem), idFromContext(fileContext),
                               newSize, setAllocationSize, info)

    func fspCanDelete(fileSystem: *FspFileSystem, fileContext: #null *void,
                      path: #null [*] u16)->s32
    {
        discard path
        return callbackCanDelete(mountedVolume(fileSystem), idFromContext(fileContext))
    }

    func fspRename(fileSystem: *FspFileSystem, fileContext: #null *void,
                   oldPath, newPath: #null [*] u16, replace: u8)->s32
    {
        let oldValue = stringFromWide(oldPath)
        let newValue = stringFromWide(newPath)
        return callbackRename(mountedVolume(fileSystem), idFromContext(fileContext),
            oldValue.buffer, newValue.buffer, replace)
    }

    func fspGetSecurity(fileSystem: *FspFileSystem, fileContext: #null *void,
                        security: #null *void, securitySize: *u64)->s32
        => copySecurity(fileSystem, idFromContext(fileContext), security, securitySize)

    func fspSetSecurity(fileSystem: *FspFileSystem, fileContext: #null *void,
                        information: u32, modification: #null *void)->s32
    {
        let context = mountContext(fileSystem)
        let nodeId = idFromContext(fileContext)
        let node = context.volume.nodeById(nodeId)
        if !node do
            return SCrypt.StatusObjectNameNotFound

        let stored = (notnull node).security.toSlice()
        let input = @countof(stored) ? cast(#null const *void) @dataof(stored) : context.defaultSecurity
        var updated: #null *void
        let status = (g_WinFsp.setSecurityDescriptor)(input, information, modification, &updated)
        if status != SCrypt.StatusSuccess do
            return status

        let size = GetSecurityDescriptorLength(updated)
        let result = callbackSetSecurity(context.volume, nodeId, updated, size)
        (g_WinFsp.deleteSecurityDescriptor)(updated, g_WinFsp.setSecurityAddress)
        return result
    }

    func emitFspDir(emitContext: #null *void, name: #null const [*] u8,
                    info: const *FileInfo)->u8
    {
        let context = cast(*FspEmitContext) notnull emitContext
        let name16 = Utf16.toZeroTerminated(cString(name))
        let bytes = #offsetof(FspDirInfo.fileName) + @countof(name16) * #sizeof(u16)
        if bytes > Swag.U16.Max do
            return 0

        var storage: Array'u8
        storage.resize(bytes)
        @memset(storage.buffer, 0, bytes)
        let dirInfo = cast(*FspDirInfo) notnull storage.buffer
        dirInfo.size = cast(u16) bytes
        dirInfo.fileInfo = dref info
        if @countof(name16) > 1 do
            @memcpy(&dirInfo.fileName[0], @dataof(name16), (@countof(name16) - 1) * #sizeof(u16))
        return (g_WinFsp.addDirInfo)(dirInfo, context.buffer, context.length, context.transferred)
    }

    func fspReadDirectory(fileSystem: *FspFileSystem, fileContext: #null *void,
                          pattern, marker: #null [*] u16, buffer: #null *void,
                          length: u32, transferred: *u32)->s32
    {
        discard pattern
        let markerValue = stringFromWide(marker)
        var context = FspEmitContext{buffer: buffer, length: length, transferred: transferred}
        var complete: u8
        let status = callbackReadDirectory(mountedVolume(fileSystem), idFromContext(fileContext),
            markerValue.buffer, &emitFspDir, &context, &complete)
        if status == SCrypt.StatusSuccess and complete do
            discard (g_WinFsp.addDirInfo)(null, buffer, length, transferred)
        return status
    }

    func fspGetDirInfoByName(fileSystem: *FspFileSystem, fileContext: #null *void,
                             name: #null [*] u16, dirInfo: *FspDirInfo)->s32
    {
        let value = stringFromWide(name)
        var info: FileInfo
        let status = callbackGetDirInfoByName(mountedVolume(fileSystem),
            idFromContext(fileContext), value.buffer, &info)
        if status != SCrypt.StatusSuccess do
            return status

        let name16 = Utf16.toZeroTerminated(value)
        let bytes = #offsetof(FspDirInfo.fileName) + @countof(name16) * #sizeof(u16)
        if bytes > Swag.U16.Max do
            return SCrypt.StatusInvalidParameter
        dirInfo.size = cast(u16) bytes
        dirInfo.fileInfo = info
        if @countof(name16) > 1 do
            @memcpy(&dirInfo.fileName[0], @dataof(name16), (@countof(name16) - 1) * #sizeof(u16))
        return SCrypt.StatusSuccess
    }

    func makeInterface()->FspInterface
    {
        var result: retval
        result.getVolumeInfo     = &fspGetVolumeInfo
        result.setVolumeLabel    = &fspSetVolumeLabel
        result.getSecurityByName = &fspGetSecurityByName
        result.create            = &fspCreate
        result.open              = &fspOpen
        result.overwrite         = &fspOverwrite
        result.cleanup           = &fspCleanup
        result.close             = &fspClose
        result.read              = &fspRead
        result.write             = &fspWrite
        result.flush             = &fspFlush
        result.getFileInfo       = &fspGetFileInfo
        result.setBasicInfo      = &fspSetBasicInfo
        result.setFileSize       = &fspSetFileSize
        result.canDelete         = &fspCanDelete
        result.rename            = &fspRename
        result.getSecurity       = &fspGetSecurity
        result.setSecurity       = &fspSetSecurity
        result.readDirectory     = &fspReadDirectory
        result.getDirInfoByName  = &fspGetDirInfoByName
        return result
    }

    var g_FspInterface: FspInterface
    var g_FspInterfaceReady: bool

    #[Swag.NoCopy]
    struct WinFspMount
    {
        fileSystem: #null *FspFileSystem
        context:    #null *NativeMountContext
    }

    impl WinFspMount
    {
        func start(result: *WinFspMount, volume: *SCrypt.Volume, mountPoint: string) fail
        {
            try loadWinFsp()
            discard catch registerPortableWinFsp() as registerError
            if registerError != null
            {
                result.stop()
                fail registerError
            }
            traceWinFspStage("portable driver registration complete")

            if !g_FspInterfaceReady
            {
                traceWinFspStage("building FSP_FILE_SYSTEM_INTERFACE")
                g_FspInterface = makeInterface()
                g_FspInterfaceReady = true
                traceWinFspStage("FSP_FILE_SYSTEM_INTERFACE ready")
            }

            result.context = Memory.new'NativeMountContext()
            result.context.volume = volume
            let sddl = Utf16.toZeroTerminated("O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;FA;;;WD)")
            if !ConvertStringSecurityDescriptorToSecurityDescriptorW(
                    @dataof(sddl), SddlRevisionOne, &result.context.defaultSecurity, null)
            {
                result.stop()
                SCrypt.failWith("Windows could not create the volume security descriptor.")
            }
            traceWinFspStage("default security descriptor created")

            traceWinFspStage("initializing FSP_FSCTL_VOLUME_PARAMS")
            var params: FspVolumeParams
            params.version                  = cast(u16) #sizeof(params)
            params.sectorSize               = 512
            params.sectorsPerAllocationUnit = 8
            params.maxComponentLength       = 255
            traceWinFspStage("volume geometry initialized")
            params.volumeCreationTime       = SCrypt.volumeTimeNow()
            params.volumeSerialNumber       = volumeSerialNumber(params.volumeCreationTime)
            traceWinFspStage("volume identity initialized")
            params.fileInfoTimeout          = 1000
            params.flags                    = (1'u32 << 1) | (1'u32 << 2) | (1'u32 << 3) |
                                              (1'u32 << 10) | (1'u32 << 13)
            traceWinFspStage("volume flags initialized")
            let fileSystemName = Utf16.toZeroTerminated("sCrypt")
            traceWinFspStage("copying filesystem name")
            @memcpy(@dataof(params.fileSystemName), @dataof(fileSystemName),
                    @countof(fileSystemName) * #sizeof(u16))
            traceWinFspStage("FSP_FSCTL_VOLUME_PARAMS ready")

            let deviceName = Utf16.toZeroTerminated(WinFspDiskName)
            let fsCreate = g_WinFsp.fsCreate
            traceWinFspStage("calling FspFileSystemCreate")
            let createStatus = fsCreate(@dataof(deviceName), &params,
                &g_FspInterface, &result.fileSystem)
            traceWinFspStage(Format.toString("FspFileSystemCreate returned %{X}",
                                             cast(u32) createStatus))
            if createStatus != SCrypt.StatusSuccess
            {
                result.stop()
                SCrypt.failWith(Format.toString(
                    "WinFsp could not create the volume (NTSTATUS %{X}).", cast(u32) createStatus))
            }

            let fileSystem = notnull result.fileSystem
            fileSystem.userContext = result.context
            (g_WinFsp.setGuard)(fileSystem, 1)
            let mountPoint16 = Utf16.toZeroTerminated(mountPoint)
            traceWinFspStage("calling FspFileSystemSetMountPoint")
            var status = (g_WinFsp.setMountPoint)(fileSystem, @dataof(mountPoint16))
            traceWinFspStage(Format.toString("FspFileSystemSetMountPoint returned %{X}",
                                             cast(u32) status))
            if status == SCrypt.StatusSuccess
            {
                traceWinFspStage("calling FspFileSystemStartDispatcher")
                status = (g_WinFsp.startDispatcher)(fileSystem, 0)
                traceWinFspStage(Format.toString("FspFileSystemStartDispatcher returned %{X}",
                                                 cast(u32) status))
            }
            if status != SCrypt.StatusSuccess
            {
                result.stop()
                SCrypt.failWith(Format.toString(
                    "WinFsp could not mount drive % (NTSTATUS %{X}).",
                    mountPoint, cast(u32) status))
            }
            traceWinFspStage("WinFspMount initialized in place")
        }

        mtd stop()
        {
            if .fileSystem
            {
                (g_WinFsp.stopDispatcher)(notnull .fileSystem)
                (g_WinFsp.removeMountPoint)(notnull .fileSystem)
                (g_WinFsp.destroy)(notnull .fileSystem)
                .fileSystem = null
            }
            if .context
            {
                if .context.defaultSecurity do
                    discard LocalFree(.context.defaultSecurity)
                Memory.delete(notnull .context)
                .context = null
            }
            unloadWinFsp()
        }

        mtd opDrop() { .stop() }
    }

    #[Swag.NoCopy]
    struct MountedVolume
    {
        volume:     SCrypt.Volume
        volumeOpen: bool
        mount:      WinFspMount
    }

    impl MountedVolume
    {
        func open(result: *MountedVolume, path: string, password: const [..] u8,
                  mountPoint: string) fail
        {
            result.volume = SCrypt.Volume.open(path, password)
            result.volumeOpen = true
            traceWinFspStage("calling WinFspMount.start from MountedVolume.open")
            try WinFspMount.start(&result.mount, &result.volume, mountPoint)
            traceWinFspStage("WinFspMount.start returned to MountedVolume.open")
            traceWinFspStage("MountedVolume initialized in place")
        }

        mtd close() fail
        {
            .mount.stop()
            if .volumeOpen
            {
                if .volume.dirty do .volume.commit()
                .volume.close()
                .volumeOpen = false
            }
        }

        mtd opDrop() { discard catch .close() }
    }
}

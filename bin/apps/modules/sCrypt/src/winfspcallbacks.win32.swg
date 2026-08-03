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
        return err == null ? SCrypt.StatusSuccess : statusFromError(err)
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
            return statusFromError(err)
        dref nodeId = id
        if !directory and allocationSize
        {
            discard catch volume.resizeNode(id, 0) as resizeErr
            if resizeErr != null do
                return statusFromError(resizeErr)
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
        return err == null ? fillInfo(volume, nodeId, info) : statusFromError(err)
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
            return statusFromError(err)
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
            return statusFromError(err, volume.freeBlockCount() ?
                SCrypt.StatusIoDeviceError : SCrypt.StatusDiskFull)
        dref transferred = count
        return fillInfo(volume, nodeId, info)
    }

    func callbackFlush(context: #null *void, nodeId: u64, info: *FileInfo)->s32
    {
        let volume = cast(*SCrypt.Volume) notnull context
        discard catch volume.commit() as err
        if err != null do
            return statusFromError(err)
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
            return statusFromError(err)
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
        return err == null ? SCrypt.StatusSuccess : statusFromError(err, SCrypt.StatusAccessDenied)
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
}

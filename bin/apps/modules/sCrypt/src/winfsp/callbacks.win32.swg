#global if WINDOWS

using Core

namespace WinFsp
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

    alias EmitDirFn = func(emitContext: #null *void, name: #null const [*] u8, info: const *FileInfo)->u8

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

    func fillInfo(volume: *Volume, nodeId: u64, output: *FileInfo)->s32
    {
        let node = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        let validNode = node!
        with output
        {
            // Windows reports the space a file occupies, so a file always
            // rounds up to whole blocks and a directory occupies none.
            .allocationSize = validNode.isDirectory() ? 0 : (validNode.size + BlockSize - 1) / BlockSize * BlockSize
            .fileAttributes = validNode.attributes
            .fileSize       = validNode.size
            .creationTime   = validNode.creationTime
            .lastAccessTime = validNode.lastAccessTime
            .lastWriteTime  = validNode.lastWriteTime
            .changeTime     = validNode.changeTime
            .indexNumber    = validNode.id
        }

        return StatusSuccess
    }

    func callbackGetVolumeInfo(context: #null *void, total, free: *u64, label: [*] u8, labelCapacity: u32)->s32
    {
        let volume = cast(*Volume) context!
        dref total = volume.totalBytes()
        dref free  = volume.freeBytes()
        let count = Math.min(volume.label.length, cast(u64) labelCapacity - 1)
        if count do
            @memcpy(label, volume.label.buffer, count)
        label[count] = 0
        return StatusSuccess
    }

    func callbackSetVolumeLabel(context: #null *void, label: #null const [*] u8)->s32
    {
        let volume = cast(*Volume) context!
        let value  = cString(label)
        if @countof(value) > 32 * 4 do
            return StatusInvalidParameter
        volume.label = value
        volume.touchScalars()
        discard catch volume.commit() as err
        return err == null ? StatusSuccess : statusFromError(err)
    }

    func callbackLookup(context: #null *void, path: #null const [*] u8, nodeId: *u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.resolve(cString(path))
        if !node do
            return StatusObjectNameNotFound
        dref nodeId = node!.id
        return fillInfo(volume, dref nodeId, info)
    }

    func callbackCreate(context: #null *void, path: #null const [*] u8, directory: u8, attributes: u32, allocationSize: u64, security: #null const *void, securitySize: u32, nodeId: *u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume) context!
        let name   = cString(path)
        if volume.resolve(name) do
            return StatusObjectNameCollision
        let parent = volume.resolveParent(name).parent
        if !parent do
            return StatusObjectNameNotFound
        var securityBytes = @mkslice(cast(const [*] u8) @dataof(""), 0)
        if securitySize do
            securityBytes = @mkslice(cast(const [*] u8) security!, securitySize)
        let id = catch volume.createNodePending(name, directory != 0, attributes, securityBytes) as err
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

    func callbackOverwrite(context: #null *void, nodeId: u64, attributes: u32, replaceAttributes: u8, allocationSize: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        if node.isDirectory() do
            return StatusFileIsDirectory
        let validNode = node
        volume.freeNodeBlocks(validNode)
        validNode.size = 0
        if replaceAttributes do
            validNode.attributes = attributes ? attributes : FileAttributeNormal
        else do
            validNode.attributes |= attributes
        validNode.changeTime    = volumeTimeNow()
        validNode.lastWriteTime = validNode.changeTime
        volume.touch(nodeId)
        discard catch volume.commit() as err
        return err == null ? fillInfo(volume, nodeId, info) : statusFromError(err)
    }

    func callbackCleanup(context: #null *void, nodeId: u64, flags: u32)
    {
        let volume = cast(*Volume) context!
        if (flags & CleanupDelete) != 0
        {
            discard catch volume.deleteNode(nodeId)
            return
        }

        let node = volume.nodeById(nodeId)
        if !node do
            return
        let now = volumeTimeNow()
        if (flags & CleanupSetArchiveBit) != 0 do
            node.attributes |= FileAttributeArchive
        if (flags & CleanupSetLastAccessTime) != 0 do
            node.lastAccessTime = now
        if (flags & CleanupSetLastWriteTime) != 0 do
            node.lastWriteTime = now
        if (flags & CleanupSetChangeTime) != 0 do
            node.changeTime = now
        if (flags & (CleanupSetAllocationSize | CleanupSetArchiveBit | CleanupSetLastAccessTime | CleanupSetLastWriteTime | CleanupSetChangeTime)) != 0 do
            volume.touch(nodeId)

        // A create is intentionally pending until cleanup so its initial data
        // and timestamps share one journal record. Cleanup has no result
        // channel, just as before, so an explicit Flush remains the path that
        // reports a durability failure to Windows.
        if volume.hasPendingChanges() do
            discard catch volume.commit()
    }

    func callbackRead(context: #null *void, nodeId: u64, buffer: #null *void, offset: u64, length: u32, transferred: *u32)->s32
    {
        if !length
        {
            dref transferred = 0
            return StatusSuccess
        }

        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        if node!.isDirectory() do
            return StatusFileIsDirectory
        let count = catch volume.readNode(nodeId, offset, @mkslice(cast([*] u8) buffer!, length)) as err
        if err != null do
            return statusFromError(err)
        dref transferred = count
        return StatusSuccess
    }

    func callbackWrite(context: #null *void, nodeId: u64, buffer: #null const *void, offset: u64, length: u32, writeToEnd, constrained: u8, transferred: *u32, info: *FileInfo)->s32
    {
        if !length
        {
            dref transferred = 0
            return callbackGetFileInfo(context, nodeId, info)
        }

        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        let validNode = node!
        if validNode.isDirectory() do
            return StatusFileIsDirectory
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
                return StatusInvalidParameter
            let firstBlock = writeOffset / BlockSize
            let lastBlock  = (writeOffset + writeLength - 1) / BlockSize
            var needed     = lastBlock - firstBlock + 1
            if !constrained and writeOffset + writeLength > validNode.size and validNode.size % BlockSize != 0 and validNode.blockSearch(validNode.size / BlockSize).found do
                needed += 1
            if volume.freeBlockCount() < needed do
                return StatusDiskFull
        }

        let count = catch volume.writeNode(nodeId, offset, @mkslice(cast(const [*] u8) buffer!, length), writeToEnd != 0, constrained != 0) as err
        if err != null do
            return statusFromError(err, volume.freeBlockCount() ? StatusIoDeviceError : StatusDiskFull)
        dref transferred = count
        return fillInfo(volume, nodeId, info)
    }

    func callbackFlush(context: #null *void, nodeId: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume) context!
        discard catch volume.commit() as err
        if err != null do
            return statusFromError(err)
        if nodeId do
            return fillInfo(volume, nodeId, info)
        return StatusSuccess
    }

    func callbackGetFileInfo(context: #null *void, nodeId: u64, info: *FileInfo)->s32
    {
        return fillInfo(cast(*Volume) context!, nodeId, info)
    }

    func callbackSetBasicInfo(context: #null *void, nodeId: u64, attributes: u32, creationTime, lastAccessTime, lastWriteTime, changeTime: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        let validNode = node!
        if attributes != Swag.U32.Max
        {
            validNode.attributes = attributes ? attributes : FileAttributeNormal
            if validNode.isDirectory() do
                validNode.attributes |= FileAttributeDirectory
            else do
                validNode.attributes &= ~FileAttributeDirectory
        }

        if creationTime do
            validNode.creationTime = creationTime
        if lastAccessTime do
            validNode.lastAccessTime = lastAccessTime
        if lastWriteTime do
            validNode.lastWriteTime = lastWriteTime
        if changeTime do
            validNode.changeTime = changeTime
        volume.touch(nodeId)
        return fillInfo(volume, nodeId, info)
    }

    func callbackSetFileSize(context: #null *void, nodeId, newSize: u64, setAllocationSize: u8, info: *FileInfo)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        let validNode = node!
        if validNode.isDirectory() do
            return StatusFileIsDirectory

        // Setting the allocation size can only shrink the node down to what it already holds.
        let targetSize = setAllocationSize ? Math.min(newSize, validNode.size) : newSize
        if targetSize > validNode.size and validNode.size % BlockSize != 0 and validNode.blockSearch(validNode.size / BlockSize).found and !volume.freeBlockCount() do
            return StatusDiskFull
        discard catch volume.resizeNode(nodeId, targetSize) as err
        if err != null do
            return statusFromError(err)
        return fillInfo(volume, nodeId, info)
    }

    func callbackCanDelete(context: #null *void, nodeId: u64)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        if nodeId == 1 do
            return StatusAccessDenied
        let validNode = node!
        if (validNode.attributes & FileAttributeReadOnly) != 0 do
            return StatusAccessDenied
        if validNode.isDirectory() and volume.hasChildren(nodeId) do
            return StatusDirectoryNotEmpty
        return StatusSuccess
    }

    func callbackRename(context: #null *void, nodeId: u64, oldPath, newPath: #null const [*] u8, replace: u8)->s32
    {
        let volume = cast(*Volume) context!
        discard oldPath
        discard catch volume.renameNode(nodeId, cString(newPath), replace != 0) as err
        return err == null ? StatusSuccess : statusFromError(err, StatusAccessDenied)
    }

    func callbackGetSecurity(context: #null *void, nodeId: u64, security: #null *void, securitySize: *u32)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        let stored    = node!.security.toSlice()
        let available = dref securitySize
        dref securitySize = cast(u32) @countof(stored)
        if !@countof(stored) do
            return StatusSuccess
        if !security or available < @countof(stored) do
            return security ? StatusBufferOverflow : StatusSuccess
        @memcpy(security!, @dataof(stored), @countof(stored))
        return StatusSuccess
    }

    func callbackSetSecurity(context: #null *void, nodeId: u64, security: #null const *void, securitySize: u32)->s32
    {
        let volume = cast(*Volume) context!
        let node   = volume.nodeById(nodeId)
        if !node do
            return StatusObjectNameNotFound
        let validNode = node!
        validNode.security.resize(securitySize)
        if securitySize do
            @memcpy(validNode.security.buffer, security!, securitySize)
        validNode.changeTime = volumeTimeNow()
        volume.touch(nodeId)
        return StatusSuccess
    }

    func sameName(left: string, right: string)->bool
    {
        return Utf8.compare(@mkslice(@dataof(left), @countof(left)), @mkslice(@dataof(right), @countof(right)), .UnicodeNoCase) == 0
    }

    func callbackReadDirectory(context: #null *void, nodeId: u64, marker: #null const [*] u8, emit: EmitDirFn, emitContext: #null *void, complete: *u8)->s32
    {
        let volume    = cast(*Volume) context!
        let directory = volume.nodeById(nodeId)
        if !directory do
            return StatusObjectNameNotFound
        if !directory!.isDirectory() do
            return StatusNotADirectory

        let markerName = cString(marker)
        var info:  FileInfo
        var child: #null *Node
        if !@countof(markerName)
        {
            if nodeId != 1
            {
                discard fillInfo(volume, nodeId, &info)
                if !emit(emitContext, @dataof("."), &info) do
                    return StatusSuccess

                let parentId = directory!.parentId
                discard fillInfo(volume, parentId, &info)
                if !emit(emitContext, @dataof(".."), &info) do
                    return StatusSuccess
            }

            child = volume.firstChild(nodeId)
        }
        elif nodeId != 1 and sameName(markerName, ".")
        {
            let parentId = directory!.parentId
            discard fillInfo(volume, parentId, &info)
            if !emit(emitContext, @dataof(".."), &info) do
                return StatusSuccess
            child = volume.firstChild(nodeId)
        }
        elif nodeId != 1 and sameName(markerName, "..") do
            child = volume.firstChild(nodeId)
        else
        {
            let markerNode = volume.findChild(nodeId, markerName)
            if markerNode do
                child = volume.nextSibling(markerNode!.id)
        }

        while child
        {
            let current = child!
            discard fillInfo(volume, current.id, &info)
            if !emit(emitContext, current.name.buffer, &info) do
                return StatusSuccess
            child = volume.nextSibling(current.id)
        }

        dref complete = 1
        return StatusSuccess
    }

    func callbackGetDirInfoByName(context: #null *void, directoryId: u64, name: #null const [*] u8, info: *FileInfo)->s32
    {
        let volume    = cast(*Volume) context!
        let directory = volume.nodeById(directoryId)
        if !directory do
            return StatusObjectNameNotFound
        let value = cString(name)
        if value == "." do
            return fillInfo(volume, directoryId, info)
        if value == ".." do
            return fillInfo(volume, directory!.parentId, info)
        let child = volume.findChild(directoryId, value)
        return child ? fillInfo(volume, child!.id, info) : StatusObjectNameNotFound
    }
}

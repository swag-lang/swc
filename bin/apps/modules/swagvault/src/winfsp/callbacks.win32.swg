#global if WINDOWS

using Core, Win32

namespace WinFsp
{
    // The information Windows keeps about a file, laid out as WinFsp expects it.
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

    // Receives one directory entry; returns 0 once the caller has no room left.
    alias EmitDirFn = func(emitContext: *void?, name: const [*] u8?, info: const *FileInfo)->u8

    // Views a zero-terminated UTF-8 string as a `string`, without copying.
    func cString(value: const [*] u8?)->string
    {
        if not value
        {
            return ""
        }

        var length = 0_u64
        while value[length]
        {
            length += 1
        }

        return Swag.makeString(value, length)
    }

    // The serial number Windows shows for the volume, taken from its creation time.
    func volumeSerialNumber(creationTime: u64)->u32
        => cast(u32, (creationTime & 0xFFFF_FFFF))

    func writableVolume(volume: *Volume)->s32
    {
        discard catch volume.requireWritable() { return statusFromError(Swag.err) }
        return StatusSuccess
    }

    // Describes a node to WinFsp: its sizes, attributes, times, and index number.
    func fillInfo(volume: *Volume, nodeId: u64, output: *FileInfo)->s32
    {
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        var allocationSize = node.size / BlockSize * BlockSize
        if node.size % BlockSize
        {
            if allocationSize > Swag.U64.Max - BlockSize
            {
                allocationSize = Swag.U64.Max
            }
            else
            {
                allocationSize += BlockSize
            }
        }

        with output
        {
            // Windows reports the space a file occupies, so a file always
            // rounds up to whole blocks and a directory occupies none.
            .allocationSize = node.isDirectory() ? 0 : allocationSize
            .fileAttributes = node.attributes
            .fileSize       = node.size
            .creationTime   = node.creationTime
            .lastAccessTime = node.lastAccessTime
            .lastWriteTime  = node.lastWriteTime
            .changeTime     = node.changeTime
            .indexNumber    = node.id
        }

        return StatusSuccess
    }

    // Reports the size, the free space, and the label of the volume, cut to `labelCapacity`.
    func callbackGetVolumeInfo(context: *void?, total, free: *u64, label: [*] u8, labelCapacity: u32)->s32
    {
        if not labelCapacity
        {
            return StatusInvalidParameter
        }

        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        total[] = volume.totalBytes()
        free[]  = volume.freeBytes()
        let bytes = volume.label.toSlice()
        var count = Math.min(bytes.count, cast(u64, labelCapacity) - 1)
        while count and count < bytes.count and (bytes[count] & 0xC0) == 0x80
        {
            count -= 1
        }

        if count
        {
            Swag.memcpy(label, &bytes[0], count)
        }

        label[count] = 0
        return StatusSuccess
    }

    // Renames the volume and commits; WinFsp stores labels in 32 UTF-16 code units.
    func callbackSetVolumeLabel(context: *void?, label: const [*] u8?)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        let value = cString(label)
        if value.count > 32 * 4 or not Utf8.isValid(value)
        {
            return StatusInvalidParameter
        }

        let bytes  = cast(const [..] u8, value)
        var offset = 0_u64
        var units  = 0_u32
        while offset < bytes.count
        {
            let {c, eat} = Utf8.decodeRune(bytes[offset to])
            units += c > 0xFFFF ? 2 : 1
            if units > 32
            {
                return StatusInvalidParameter
            }

            offset += eat
        }

        volume.label = value
        volume.touchScalars()
        var errOutcome: Swag.Error
        discard catch volume.commit() as errOutcome
        let err = errOutcome.value()
        return err == null ? StatusSuccess : statusFromError(err)
    }

    // Builds a Windows path from the stored names while the caller holds the volume lock.
    private func storedPath(volume: *Volume, node: *Node)->String
    {
        var parts: Array!{string}
        var current = node
        while current.id != RootNodeId
        {
            parts.add(current.name)
            current = unwrap volume.nodeById(current.parentId)
        }

        if not parts.count
        {
            return "\\"
        }

        var result: String
        for index in reversed(parts.count)
        {
            result.append("\\")
            result.append(parts[index])
        }

        return result
    }

    func callbackLookup(context: *void?, path: const [*] u8?, nodeId: *u64, info: *FileInfo, normalizedPath: *String? = null)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        let node = volume.resolve(cString(path))
        if not node
        {
            return StatusObjectNameNotFound
        }

        nodeId[] = node.id
        if normalizedPath
        {
            normalizedPath[] = storedPath(volume, node)
        }

        return fillInfo(volume, nodeId[], info)
    }

    // Creates a file or a directory at `path`. The record stays pending until cleanup, so the first
    // data and times are journaled with it.
    func callbackCreate(context: *void?, path: const [*] u8?, directory: u8, attributes: u32, allocationSize: u64, security: const *void?, securitySize: u32, nodeId: *u64, info: *FileInfo, normalizedPath: *String? = null)->s32
    {
        if securitySize and not security
        {
            return StatusInvalidParameter
        }

        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let name = cString(path)
        if volume.resolve(name)
        {
            return StatusObjectNameCollision
        }

        let parent = volume.resolveParent(name).parent
        if not parent
        {
            return StatusObjectNameNotFound
        }

        var securityBytes = cast(const [..] u8, "")
        if securitySize
        {
            securityBytes = Swag.makeSlice(cast(const [*] u8, unwrap security), securitySize)
        }

        let id = catch volume.createNodePending(name, directory != 0, attributes, securityBytes) { return statusFromError(Swag.err) }
        nodeId[] = id
        if not directory and allocationSize
        {
            discard catch volume.resizeNode(id, 0) { return statusFromError(Swag.err) }
        }

        if normalizedPath
        {
            normalizedPath[] = storedPath(volume, unwrap volume.nodeById(id))
        }

        return fillInfo(volume, id, info)
    }

    // Empties a file opened for overwrite, and replaces or merges its attributes.
    func callbackOverwrite(context: *void?, nodeId: u64, attributes: u32, replaceAttributes: u8, _: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        if node.isDirectory()
        {
            return StatusFileIsDirectory
        }

        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        if (node.attributes & FileAttributeReadOnly) != 0
        {
            return StatusAccessDenied
        }

        volume.freeNodeBlocks(node)
        node.size = 0
        if replaceAttributes
        {
            node.attributes = attributes ? attributes : FileAttributeNormal
        }
        else
        {
            node.attributes |= attributes
        }

        node.attributes    &= ~FileAttributeDirectory
        node.changeTime    = volumeTimeNow()
        node.lastWriteTime = node.changeTime
        volume.touch(nodeId)
        var errOutcome: Swag.Error
        discard catch volume.commit() as errOutcome
        let err = errOutcome.value()
        return err == null ? fillInfo(volume, nodeId, info) : statusFromError(err)
    }

    // Runs when the last handle closes: deletes the node when asked, applies the requested time and
    // attribute updates, and commits what is pending.
    func callbackCleanup(context: *void?, nodeId: u64, flags: u32)
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        if writableVolume(volume) != StatusSuccess
        {
            return
        }

        if (flags & CleanupDelete) != 0
        {
            discard catch volume.deleteNode(nodeId)
            return
        }

        let node = volume.nodeById(nodeId)
        if not node
        {
            return
        }

        let now = volumeTimeNow()
        if (flags & CleanupSetArchiveBit) != 0
        {
            node.attributes |= FileAttributeArchive
        }

        if (flags & CleanupSetLastAccessTime) != 0
        {
            node.lastAccessTime = now
        }

        if (flags & CleanupSetLastWriteTime) != 0
        {
            node.lastWriteTime = now
        }

        if (flags & CleanupSetChangeTime) != 0
        {
            node.changeTime = now
        }

        if (flags & (CleanupSetAllocationSize |
                     CleanupSetArchiveBit |
                     CleanupSetLastAccessTime |
                     CleanupSetLastWriteTime |
                     CleanupSetChangeTime)) != 0
        {
            volume.touchMetadata(nodeId)
        }

        // A create is intentionally pending until cleanup so its initial data
        // and timestamps share one journal record. Cleanup has no result
        // channel, just as before, so an explicit Flush remains the path that
        // reports a durability failure to Windows.
        if volume.hasPendingChanges()
        {
            discard catch volume.commit()
        }
    }

    // Reads up to `length` bytes of a file at `offset` into `buffer`, and reports how many it
    // read.
    func callbackRead(context: *void?, nodeId: u64, buffer: *void?, offset: u64, length: u32, transferred: *u32)->s32
    {
        if not length
        {
            transferred[] = 0
            return StatusSuccess
        }

        let volume = cast(*Volume, unwrap context)
        #static if #hastag("vault.integration")
        {
            let started = Time.monotonicMicroseconds()
        }

        #static if #hastag("vault.integration")
        {
            defer Atomic.add(&Integration.g_ReadCallbackMicroseconds, Time.monotonicMicroseconds() - started)
        }

        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        if node.isDirectory()
        {
            return StatusFileIsDirectory
        }

        let count = catch volume.readNode(nodeId, offset, Swag.makeSlice(cast([*] u8, unwrap buffer), length)) { return statusFromError(Swag.err) }
        transferred[] = count
        return StatusSuccess
    }

    // Writes to a file, at its end or within its size when asked, once the blocks it needs are
    // known to be free.
    func callbackWrite(context: *void?, nodeId: u64, buffer: const *void?, offset: u64, length: u32, writeToEnd, constrained: u8, transferred: *u32, info: *FileInfo)->s32
    {
        if not length
        {
            transferred[] = 0
            return callbackGetFileInfo(context, nodeId, info)
        }

        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        if node.isDirectory()
        {
            return StatusFileIsDirectory
        }

        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        if (node.attributes & FileAttributeReadOnly) != 0
        {
            return StatusAccessDenied
        }

        var writeOffset = writeToEnd ? node.size : offset
        var writeLength = cast(u64, length)
        if constrained
        {
            if writeOffset >= node.size
            {
                writeLength = 0
            }
            else
            {
                writeLength = Math.min(writeLength, node.size - writeOffset)
            }
        }

        if writeLength
        {
            if writeOffset > Swag.U64.Max - writeLength
            {
                return StatusInvalidParameter
            }

            let firstBlock = writeOffset / BlockSize
            let lastBlock  = (writeOffset + writeLength - 1) / BlockSize
            var needed     = lastBlock - firstBlock + 1
            if not constrained and
               writeOffset + writeLength > node.size and
               node.size % BlockSize != 0 and
               node.blockSearch(node.size / BlockSize).found
            {
                needed += 1
            }

            if volume.freeBlockCount() < needed
            {
                return StatusDiskFull
            }
        }

        let count = catch volume.writeNode(nodeId, offset, Swag.makeSlice(cast(const [*] u8, unwrap buffer), length), writeToEnd != 0, constrained != 0) { return statusFromError(Swag.err, volume.freeBlockCount() ? StatusIoDeviceError : StatusDiskFull) }
        transferred[] = count
        return fillInfo(volume, nodeId, info)
    }

    // Commits every pending change, which is how Windows learns of a durability failure.
    func callbackFlush(context: *void?, nodeId: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        discard catch volume.commit() { return statusFromError(Swag.err) }
        if nodeId
        {
            return fillInfo(volume, nodeId, info)
        }

        return StatusSuccess
    }

    func callbackGetFileInfo(context: *void?, nodeId: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        return fillInfo(volume, nodeId, info)
    }

    // Changes the attributes and times Windows passes; a zero time, or `U32.Max` attributes, keeps
    // the current value.
    func callbackSetBasicInfo(context: *void?, nodeId: u64, attributes: u32, creationTime, lastAccessTime, lastWriteTime, changeTime: u64, info: *FileInfo)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        if attributes != Swag.U32.Max
        {
            let isDirectory = node.isDirectory()
            node.attributes = attributes ? attributes : FileAttributeNormal
            if isDirectory
            {
                node.attributes |= FileAttributeDirectory
            }
            else
            {
                node.attributes &= ~FileAttributeDirectory
            }
        }

        if creationTime
        {
            node.creationTime = creationTime
        }

        if lastAccessTime
        {
            node.lastAccessTime = lastAccessTime
        }

        if lastWriteTime
        {
            node.lastWriteTime = lastWriteTime
        }

        if changeTime
        {
            node.changeTime = changeTime
        }

        volume.touchMetadata(nodeId)
        return fillInfo(volume, nodeId, info)
    }

    // Changes the size of a file, or only trims what it holds when Windows sets its allocation
    // size, refusing a growth the volume has no block left for.
    func callbackSetFileSize(context: *void?, nodeId, newSize: u64, setAllocationSize: u8, info: *FileInfo)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        if node.isDirectory()
        {
            return StatusFileIsDirectory
        }

        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        if (node.attributes & FileAttributeReadOnly) != 0
        {
            return StatusAccessDenied
        }

        // Setting the allocation size can only shrink the node down to what it already holds.
        let targetSize = setAllocationSize ? Math.min(newSize, node.size) : newSize
        if targetSize > node.size and
           node.size % BlockSize != 0 and
           node.blockSearch(node.size / BlockSize).found and
           not volume.freeBlockCount()
        {
            return StatusDiskFull
        }

        discard catch volume.resizeNode(nodeId, targetSize) { return statusFromError(Swag.err) }
        return fillInfo(volume, nodeId, info)
    }

    // Refuses to delete the root, a read-only node, or a directory that is not empty.
    func callbackCanDelete(context: *void?, nodeId: u64)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        if nodeId == 1
        {
            return StatusAccessDenied
        }

        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        if (node.attributes & FileAttributeReadOnly) != 0
        {
            return StatusAccessDenied
        }

        if node.isDirectory() and volume.hasChildren(nodeId)
        {
            return StatusDirectoryNotEmpty
        }

        return StatusSuccess
    }

    // Moves a node to `newPath`, over an existing target when `replace` allows it.
    func callbackRename(context: *void?, nodeId: u64, _, newPath: const [*] u8?, replace: u8)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        var errOutcome: Swag.Error
        discard catch volume.renameNode(nodeId, cString(newPath), replace != 0) as errOutcome
        let err = errOutcome.value()
        return err == null ? StatusSuccess : statusFromError(err, StatusAccessDenied)
    }

    // Copies the security descriptor of a node; without a buffer, only reports its size.
    func callbackGetSecurity(context: *void?, nodeId: u64, security: *void?, securitySize: *u32)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        let stored    = node.security.toSlice()
        let available = securitySize[]
        securitySize[] = cast(u32, stored.count)
        if not stored.count
        {
            return StatusSuccess
        }

        if not security or available < stored.count
        {
            return security ? StatusBufferOverflow : StatusSuccess
        }

        Swag.memcpy(security, stored.buffer, stored.count)
        return StatusSuccess
    }

    func callbackSetSecurity(context: *void?, nodeId: u64, security: const *void?, securitySize: u32)->s32
    {
        if securitySize > MaximumSecuritySize or (securitySize and not security)
        {
            return StatusInvalidParameter
        }

        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lock()
        defer volume.accessLock.unlock()
        let node = volume.nodeById(nodeId)
        if not node
        {
            return StatusObjectNameNotFound
        }

        let writableStatus = writableVolume(volume)
        if writableStatus != StatusSuccess
        {
            return writableStatus
        }

        node.security.resize(securitySize)
        if securitySize
        {
            Swag.memcpy(node.security.storage(), unwrap security, securitySize)
        }

        node.changeTime = volumeTimeNow()
        volume.touch(nodeId)
        return StatusSuccess
    }

    // Compares two names the way Windows does, ignoring case.
    func sameName(left: string, right: string)->bool => Utf8.compare(left, right, .UnicodeNoCase) == 0

    // Lists a directory from after `marker`, with `.` and `..` first except at the root, until
    // `emit` has no room left.
    func callbackReadDirectory(context: *void?, nodeId: u64, marker: const [*] u8?, emit: EmitDirFn, emitContext: *void?, complete: *u8)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        let directory = volume.nodeById(nodeId)
        if not directory
        {
            return StatusObjectNameNotFound
        }

        if not directory.isDirectory()
        {
            return StatusNotADirectory
        }

        let markerName = cString(marker)
        var info:  FileInfo
        var child: *Node?
        if not markerName.count
        {
            if nodeId != 1
            {
                discard fillInfo(volume, nodeId, &info)
                if not emit(emitContext, (".").buffer, &info)
                {
                    return StatusSuccess
                }

                let parentId = directory.parentId
                discard fillInfo(volume, parentId, &info)
                if not emit(emitContext, ("..").buffer, &info)
                {
                    return StatusSuccess
                }
            }

            child = volume.firstChild(nodeId)
        }
        else if nodeId != 1 and sameName(markerName, ".")
        {
            let parentId = directory.parentId
            discard fillInfo(volume, parentId, &info)
            if not emit(emitContext, ("..").buffer, &info)
            {
                return StatusSuccess
            }

            child = volume.firstChild(nodeId)
        }
        else if nodeId != 1 and sameName(markerName, "..")
        {
            child = volume.firstChild(nodeId)
        }
        else
        {
            let markerNode = volume.findChild(nodeId, markerName)
            if markerNode
            {
                child = volume.nextSibling(markerNode.id)
            }
        }

        while child
        {
            let current = child
            discard fillInfo(volume, current.id, &info)
            if not emit(emitContext, current.name.buffer, &info)
            {
                return StatusSuccess
            }

            child = volume.nextSibling(current.id)
        }

        complete[] = 1
        return StatusSuccess
    }

    // Reports the entry `name` of a directory, `.` and `..` included.
    func callbackGetDirInfoByName(context: *void?, directoryId: u64, name: const [*] u8?, info: *FileInfo, storedName: *String)->s32
    {
        let volume = cast(*Volume, unwrap context)
        volume.accessLock.lockShared()
        defer volume.accessLock.unlockShared()
        let directory = volume.nodeById(directoryId)
        if not directory
        {
            return StatusObjectNameNotFound
        }

        if not directory.isDirectory()
        {
            return StatusNotADirectory
        }

        let value = cString(name)
        if value == "." or value == ".."
        {
            storedName[] = value
            return fillInfo(volume, value == "." ? directoryId : directory.parentId, info)
        }

        let child = volume.findChild(directoryId, value)
        if not child
        {
            return StatusObjectNameNotFound
        }

        storedName[] = child.name
        return fillInfo(volume, child.id, info)
    }
}

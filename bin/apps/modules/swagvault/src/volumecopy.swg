using Core

// Streams a namespace into another volume without writing plaintext to the host filesystem.
struct VolumeCopy
{
    source: *Volume
    target: *Volume
    files:  u64
    bytes:  u64
}

impl VolumeCopy
{
    mtd copyDirectory(parent: u64, prefix: string) fail
    {
        for node in .source.nodes where node.id != RootNodeId and node.parentId == parent
        {
            let path = Format.toString("%\\%", prefix, node.name)
            let id   = try .target.createNode(path, node.isDirectory(), node.attributes & ~FileAttributeReadOnly, node.security.toSlice())
            if node.isDirectory() do
                try .copyDirectory(node.id, path.toString())
            else
            {
                var buffer: Array'u8
                buffer.resize(MaximumIoBatchBlocks * BlockSize)
                defer Core.Crypto.secureClear(buffer.toSlice())
                var offset = 0'u64
                while offset < node.size
                {
                    let count = Math.min(buffer.count, node.size - offset)
                    if (try .source.readNode(node.id, offset, buffer[until count])) != count do
                        failWith("The source file ended before its declared size.", .Io)
                    if (try .target.writeNode(id, offset, buffer[until count], false, false)) != count do
                        failWith("The destination did not accept the complete transfer.", .Io)
                    offset += count
                    .bytes += count
                }

                .files += 1
            }

            let copied = .target.nodeById(id)!
            copied.attributes     = node.attributes
            copied.creationTime   = node.creationTime
            copied.lastAccessTime = node.lastAccessTime
            copied.lastWriteTime  = node.lastWriteTime
            copied.changeTime     = node.changeTime
            .target.touch(id)
            try .target.commit()
        }
    }

    // Reopening before verification tests the durable data and every namespace entry.
    mtd verifyDirectory(parent: u64, prefix: string) fail
    {
        for node in .source.nodes where node.id != RootNodeId and node.parentId == parent
        {
            let path  = Format.toString("%\\%", prefix, node.name)
            let found = .target.resolve(path)
            if !found do
                failWith("A copied entry is missing.", .Io)
            let copied = found!
            if copied.size != node.size or copied.attributes != node.attributes or copied.creationTime != node.creationTime or copied.lastAccessTime != node.lastAccessTime or copied.lastWriteTime != node.lastWriteTime or copied.changeTime != node.changeTime or !Core.Crypto.constantTimeEqual(copied.security.toSlice(), node.security.toSlice()) do
                failWith("Copied metadata differs from the source.", .Io)
            if node.isDirectory() do
                try .verifyDirectory(node.id, path.toString())
            else
            {
                var original, restored: Array'u8
                original.resize(MaximumIoBatchBlocks * BlockSize)
                restored.resize(original.count)
                defer Core.Crypto.secureClear(original.toSlice())
                defer Core.Crypto.secureClear(restored.toSlice())
                var offset = 0'u64
                while offset < node.size
                {
                    let count = Math.min(original.count, node.size - offset)
                    if (try .source.readNode(node.id, offset, original[until count])) != count or
                       (try .target.readNode(copied.id, offset, restored[until count])) != count or
                       !Core.Crypto.constantTimeEqual(original[until count], restored[until count]) do
                        failWith("Copied bytes differ from the source.", .Io)
                    offset += count
                }
            }
        }
    }
}

#static if #hastag("vault.hidden-copy")
{
    // Dedicated repository harness: paths and credentials come from the child environment, never
    // from command-line arguments or a configuration file. The source is opened read only.
    func runHiddenCopy() fail
    {
        let sourcePath     = Env.variable("SWAG_VAULT_COPY_SOURCE")
        let targetPath     = Env.variable("SWAG_VAULT_COPY_TARGET")
        var outerPassword  = Env.variable("SWAG_VAULT_COPY_PASSWORD")
        var hiddenPassword = Env.variable("SWAG_VAULT_COPY_HIDDEN_PASSWORD")
        defer Core.Crypto.secureClear(outerPassword.toSlice())
        defer Core.Crypto.secureClear(hiddenPassword.toSlice())
        if sourcePath.isEmpty() or targetPath.isEmpty() or outerPassword.isEmpty() or hiddenPassword.isEmpty() do
            failWith("The copy harness needs source, target, and both access variables.", .InvalidInput)
        Console.println("Opening source read only...")
        var source = try Volume.open(sourcePath, outerPassword.toSlice(), true)
        Console.println("Source entries: ", source.nodes.count, "; capacity: ", source.containerSize)

        // Keep the source capacity for future hidden files and a further GiB for ordinary files.
        let hiddenSize = source.containerSize
        let reserve    = 1'u64 * 1024 * 1024 * 1024
        let outerSize  = DataOffset + hiddenSize + (reserve / BlockSize + 16) * BlockRecordSize
        Console.println("Creating outer container; hidden capacity: ", hiddenSize, "; outer reserve: ", reserve)
        var outer = try Volume.create(targetPath, outerPassword.toSlice(), outerSize)
        outer.close()
        var target = try Volume.createHidden(targetPath, outerPassword.toSlice(), hiddenPassword.toSlice(), hiddenSize, outerReserve: reserve)
        Console.println("Copying files into the hidden volume...")
        var copier = VolumeCopy{&source, &target}
        try copier.copyDirectory(RootNodeId, "")
        try target.checkpoint()
        target.close()
        Console.println("Reopening and comparing every copied byte...")
        var verified = try Volume.open(targetPath, hiddenPassword.toSlice(), true)
        copier.target = &verified
        if verified.nodes.count != source.nodes.count do
            failWith("The copied namespace has a different number of entries.", .Io)
        try copier.verifyDirectory(RootNodeId, "")
        verified.close()
        Console.println("Checking ordinary writes with hidden protection enabled...")
        var protected = try Volume.open(targetPath, outerPassword.toSlice(), protectionPassword: hiddenPassword.toSlice())
        let marker    = try protected.createNode("\\readme.txt", false, FileAttributeNormal, "")
        let text      = "Private virtual drive.\n"
        discard try protected.writeNode(marker, 0, text, false, false)
        try protected.commit()
        protected.close()
        var finalCheck = try Volume.open(targetPath, hiddenPassword.toSlice(), true)
        copier.target = &finalCheck
        try copier.verifyDirectory(RootNodeId, "")
        Console.println("PASS: ", copier.files, " files; ", copier.bytes, " bytes verified; source unchanged.")
    }
}

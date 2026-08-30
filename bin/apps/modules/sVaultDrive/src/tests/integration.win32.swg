#global if WINDOWS and #hastag("SVaultDrive.Integration")

#foreignlib("kernel32")

using Core

namespace Integration
{
    const PasswordText            = "integration horse battery staple"
    const WrongPasswordText       = "definitely not the password"
    const VisibilityProbeArgument = "--integration-drive-probe"
    const ContainerSize           = 64'u64 * 1024 * 1024
    const LargeMoveSize           = 16'u64 * 1024 * 1024 + 37
    const MaximumRenameDurationMs = 5000'u64
    const FileAttributeReadOnly   = 0x00000001'u32
    const FileAttributeNormal     = 0x00000080'u32
    const MoveReplaceExisting     = 0x00000001'u32

    var g_CheckCount: u32
    var g_Failure:    String

    func isVisibilityProbeInvocation()->bool
    {
        let args = Env.arguments()
        return args.count >= 3 and args[1] == VisibilityProbeArgument
    }

    func runVisibilityProbe()->s32
    {
        let args = Env.arguments()
        if args.count < 3 do
            return 2
        let payload = "VISIBLE"
        discard catch File.writeAllBytes(args[2], Swag.makeSlice(cast(const [*] u8) payload.buffer, payload.count)) as writeError
        return writeError == null ? 0 : 1
    }

    #[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
    {
        func MoveFileExW(existing, replacement: #null const [*] u16, flags: u32)->s32
        func SetFileAttributesW(path: #null const [*] u16, attributes: u32)->s32
        func GetFileAttributesW(path: #null const [*] u16)->u32
        func GetLastError()->u32
    }

    func password()->const [..] u8
    {
        return Swag.makeSlice(cast(const [*] u8) PasswordText.buffer, PasswordText.count)
    }

    func wrongPassword()->const [..] u8
    {
        return Swag.makeSlice(cast(const [*] u8) WrongPasswordText.buffer, WrongPasswordText.count)
    }

    func verify(condition: bool, message: string) fail
    {
        if !condition do
            failWith(Format.toString("Integration check failed: %", message))
        g_CheckCount += 1
    }

    func sameBytes(left, right: const [..] u8)->bool
    {
        return left.count == right.count and
               Swag.memcmp(left.buffer, right.buffer, left.count) == 0
    }

    func allZero(bytes: const [..] u8)->bool
    {
        for byte in bytes where byte != 0 do
            return false
        return true
    }

    func driveRoot(mountPoint: string)->String
        => Format.toString("%\\", mountPoint)

    func containsDriveLetter(letters: const [..] rune, expected: rune)->bool
    {
        for letter in letters where letter == expected do
            return true
        return false
    }

    func findFreeMountPoint()->String fail
    {
        let available = WinFsp.availableDriveLetters()
        for offset in 23
        {
            let index = 25'u32 - cast(u32) offset
            if containsDriveLetter(available.toSlice(), cast(rune) ('A' + index)) do
                return Format.toString("%:", cast(rune) ('A' + index))
        }

        failWith("No unused drive letter is available for the integration sandbox.")
    }

    func movePath(existing, replacement: string, replace = false) fail
    {
        let existing16    = Utf16.toZeroTerminated(existing)
        let replacement16 = Utf16.toZeroTerminated(replacement)
        if !MoveFileExW(existing16.buffer, replacement16.buffer, replace ? MoveReplaceExisting : 0) do
            failWith(Format.toString("Windows error %: cannot rename [[%]] to [[%]].", GetLastError(), existing, replacement))
    }

    func setAttributes(path: string, attributes: u32) fail
    {
        let path16 = Utf16.toZeroTerminated(path)
        if !SetFileAttributesW(path16.buffer, attributes) do
            failWith(Format.toString("Windows error %: cannot set attributes on [[%]].", GetLastError(), path))
    }

    func attributes(path: string)->u32
    {
        let path16 = Utf16.toZeroTerminated(path)
        return GetFileAttributesW(path16.buffer)
    }

    func removeDirectory(path: string) fail
    {
        let path16 = Utf16.toZeroTerminated(path)
        if !WinFsp.RemoveDirectoryW(path16.buffer) do
            failWith(Format.toString("Windows error %: cannot remove directory [[%]].", GetLastError(), path))
    }

    func containsEntry(entries: const [..] File.FileInfo, name: string)->bool
    {
        for entry in entries where (Path.fileName(entry.fullname) orelse "") == name do
            return true
        return false
    }

    func resultPath()->String
    {
        let executableDirectory = Path.directoryName(Env.executablePath()) orelse ""
        return Path.combine(executableDirectory, "sVaultDrive-integration-result.txt")
    }

    func trace(message: string)
    {
        var stream = catch File.open(resultPath(), .Append, .Write, .Read) as openError
        if openError != null do
            return
        discard catch stream.write(message.buffer!, message.count)
        discard catch stream.write(("\n").buffer, 1)
        stream.close()
    }

    #[Swag.NoCopy]
    struct Sandbox
    {
        root:          String
        container:     String
        source:        String
        recovered:     String
        mountPoint:    String
        mounted:       #null *WinFsp.MountedVolume
        mountedActive: bool
    }

    impl Sandbox
    {
        func create()->Sandbox fail
        {
            var result: retval
            let temp = Env.getSpecialDirectory(.Temp)
            if temp.isEmpty() do
                failWith("Windows did not provide a temporary directory for the sandbox.")
            result.root = Path.combine(temp, Format.toString("sVaultDrive-Integration-%", Guid64.random()))
            Directory.create(result.root)
            result.container  = Path.combine(result.root, "integration")
            result.source     = Path.combine(result.root, "external-source.bin")
            result.recovered  = Path.combine(result.root, "recovered-from-volume.bin")
            result.mountPoint = try findFreeMountPoint()
            return result
        }

        mtd mountVolume(passwordBytes: const [..] u8) fail
        {
            if .mountedActive do
                failWith("The integration volume is already mounted.")
            let mounted = Memory.new'WinFsp.MountedVolume()
            discard catch mounted.open(.container, passwordBytes, .mountPoint) as mountError
            if mountError != null
            {
                Memory.delete(mounted)
                fail mountError
            }

            .mounted       = mounted
            .mountedActive = true
        }

        mtd unmountVolume() fail
        {
            if !.mountedActive do
                return
            let mounted = .mounted!
            discard catch mounted.close() as closeError
            Memory.delete(mounted)
            .mounted       = null
            .mountedActive = false
            if closeError != null do
                fail closeError
        }

        mtd cleanup()
        {
            if .mountedActive
            {
                let mounted = .mounted!
                discard catch mounted.close()
                Memory.delete(mounted)
                .mounted       = null
                .mountedActive = false
            }

            if !.root.isEmpty() do
                WinFsp.removeRuntimeTree(.root)
        }

        mtd closeSandbox() fail
        {
            if .mountedActive do
                try .unmountVolume()
            WinFsp.removeRuntimeTree(.root)
            if Directory.exists(.root) do
                failWith(Format.toString("The integration sandbox could not be removed: %", .root))
            .root.clear()
        }

        mtd opDrop() { .cleanup() }
    }

    func createPayload(size: u64)->Array'u8 fail
    {
        var result: retval
        result.resize(size)
        try Core.Crypto.randomBytes(result.toSlice())
        return result
    }

    func runFilesystemScenarios(box: *Sandbox, original: const [..] u8) fail
    {
        let root      = driveRoot(box.mountPoint)
        let documents = Path.combine(root, "Documents")
        let nested    = Path.combine(documents, "Nested")
        trace("FS: create nested directories")
        Directory.create(documents)
        Directory.create(nested)
        try verify(Directory.exists(documents) and Directory.exists(nested), "nested directories must be creatable")

        let persistent = Path.combine(nested, "external-copy.bin")
        trace("FS: external copy round trip")
        File.duplicate(persistent, box.source)
        try verify(File.exists(persistent), "an external file must copy into the mounted drive")
        File.duplicate(box.recovered, persistent)
        let firstRecovery = try File.readAllBytes(box.recovered)
        try verify(sameBytes(original, firstRecovery.toSlice()), "a copied file must survive a round trip through the mounted drive")

        let empty = Path.combine(documents, "empty.txt")
        trace("FS: empty file")
        discard File.writeAllBytes(empty, Swag.makeSlice(cast(const [*] u8) ("").buffer, 0))
        try verify(File.exists(empty) and (try File.openRead(empty)).size() == 0, "zero-length files must be supported")

        let unicode = Path.combine(documents, "résumé-東京.txt")
        trace("FS: Unicode file")
        let unicodePayload = "UTF-8 names are preserved"
        discard File.writeAllBytes(unicode, Swag.makeSlice(cast(const [*] u8) unicodePayload.buffer, unicodePayload.count))
        let unicodeRead = try File.readAllText(unicode)
        try verify(unicodeRead == unicodePayload, "Unicode file names and text must round-trip")

        let overwrite = Path.combine(documents, "overwrite.bin")
        trace("FS: overwrite and append")
        let first:  [7] u8 = [1, 2, 3, 4, 5, 6, 7]
        let second: [3] u8 = [9, 8, 7]
        discard File.writeAllBytes(overwrite, first)
        discard File.writeAllBytes(overwrite, second)
        let overwritten = try File.readAllBytes(overwrite)
        try verify(sameBytes(overwritten.toSlice(), second), "overwriting must truncate and replace an existing file")

        var appendStream     = try File.open(overwrite, .Append, .Write, .Zero)
        let appended: [4] u8 = [6, 5, 4, 3]
        discard try appendStream.write(&appended[0], #sizeof(appended))
        appendStream.close()
        let afterAppend            = try File.readAllBytes(overwrite)
        let expectedAppend: [7] u8 = [9, 8, 7, 6, 5, 4, 3]
        try verify(sameBytes(afterAppend.toSlice(), expectedAppend), "append mode must add data at end of file")

        let sparse = Path.combine(documents, "sparse.bin")
        trace("FS: sparse file")
        var sparseStream = try File.open(sparse, .CreateNew, .Write, .Zero)
        try sparseStream.seek(.Begin, 128 * 1024 + 17)
        let marker: [5] u8 = [0x51, 0x52, 0x53, 0x54, 0x55]
        discard try sparseStream.write(&marker[0], #sizeof(marker))
        sparseStream.close()
        let sparseData = try File.readAllBytes(sparse)
        try verify(sparseData.count == 128 * 1024 + 17 + #sizeof(marker), "a sparse write must extend the file to the requested offset")
        try verify(allZero(Swag.makeSlice(sparseData.buffer, 128 * 1024 + 17)), "sparse holes must read back as zero")
        try verify(Swag.memcmp(sparseData.buffer + 128 * 1024 + 17, &marker[0], #sizeof(marker)) == 0, "the sparse tail must retain its data")

        let renamed = Path.combine(documents, "renamed.bin")
        trace("FS: file and directory rename")
        movePath(overwrite, renamed)
        try verify(!File.exists(overwrite) and File.exists(renamed), "files must be renameable")

        // Explorer computes progress while cached writes and namespace notifications are still
        // active. WinFsp 2.1 could deadlock in that overlap and leave Explorer waiting forever.
        // Keep a real multi-megabyte payload in this scenario: the subsequent move must remain a
        // bounded metadata operation and preserve the file without copying its encrypted blocks.
        let largeSource      = Path.combine(documents, "large-move-source.bin")
        let largeDestination = Path.combine(nested, "large-move-destination.bin")
        trace("FS: large file move between directories")
        var largePayload = try createPayload(LargeMoveSize)
        discard File.writeAllBytes(largeSource, largePayload.toSlice())
        var renameTimer: Time.Stopwatch
        renameTimer.start()
        movePath(largeSource, largeDestination)
        renameTimer.stop()
        let movedLargeStream = try File.openRead(largeDestination)
        let movedSize        = try movedLargeStream.size()
        movedLargeStream.close()
        try verify(renameTimer.elapsedMilliseconds() < MaximumRenameDurationMs, "moving a large file between directories must not stall the filesystem host")
        try verify(!File.exists(largeSource) and movedSize == LargeMoveSize, "a large moved file must retain its size and destination")

        let renamedNested = Path.combine(documents, "Renamed-Nested")
        movePath(nested, renamedNested)
        let movedPersistent = Path.combine(renamedNested, "external-copy.bin")
        let movedLargePath  = Path.combine(renamedNested, "large-move-destination.bin")
        try verify(!Directory.exists(nested) and File.exists(movedPersistent) and File.exists(movedLargePath), "directories with children must be renameable")

        let replacementSource = Path.combine(documents, "replacement-source.bin")
        trace("FS: rename with replacement")
        let replacementTarget        = Path.combine(documents, "replacement-target.bin")
        let replacementBytes: [5] u8 = [21, 22, 23, 24, 25]
        discard File.writeAllBytes(replacementSource, replacementBytes)
        discard File.writeAllBytes(replacementTarget, first)
        movePath(replacementSource, replacementTarget, true)
        let replacementRead = try File.readAllBytes(replacementTarget)
        try verify(!File.exists(replacementSource) and sameBytes(replacementRead.toSlice(), replacementBytes), "rename with replacement must atomically replace the destination")

        let readOnlyPath = Path.combine(documents, "readonly.bin")
        trace("FS: read-only attributes")
        discard File.writeAllBytes(readOnlyPath, first)
        try setAttributes(readOnlyPath, FileAttributeReadOnly)
        try verify((attributes(readOnlyPath) & FileAttributeReadOnly) != 0, "read-only attributes must be reported")
        discard catch File.writeAllBytes(readOnlyPath, second) as readonlyError
        try verify(readonlyError != null, "writes to read-only files must be rejected")
        try setAttributes(readOnlyPath, FileAttributeNormal)
        discard File.writeAllBytes(readOnlyPath, second)
        try verify(sameBytes((try File.readAllBytes(readOnlyPath)).toSlice(), second), "clearing read-only must allow writes again")

        let disposable = Path.combine(documents, "disposable.txt")
        trace("FS: file and directory deletion")
        discard File.writeAllBytes(disposable, first)
        try File.delete(disposable)
        try verify(!File.exists(disposable), "files must be deletable")
        let emptyDirectory = Path.combine(documents, "Empty-Directory")
        Directory.create(emptyDirectory)
        try removeDirectory(emptyDirectory)
        try verify(!Directory.exists(emptyDirectory), "empty directories must be deletable")

        let bulk = Path.combine(documents, "Bulk")
        trace("FS: bulk directory enumeration")
        Directory.create(bulk)
        for index in 24
        {
            let name = Path.combine(bulk, Format.toString("item-%.bin", index))
            var bytes: [113] u8
            for byteIndex in #sizeof(bytes) do
                bytes[byteIndex] = cast(u8) ((index * 31 + byteIndex * 17) & 0xFF)
            discard File.writeAllBytes(name, bytes)
        }

        let entries     = try Directory.enumerateFiles(bulk)
        let scannedBulk = entries.count == 24 and
                          containsEntry(entries.toSlice(), "item-0.bin") and
                          containsEntry(entries.toSlice(), "item-23.bin")
        try verify(scannedBulk, "directory scans must return every created file")

        let documentsEntries = try Directory.enumerate(documents, {})
        let scannedDocuments = containsEntry(documentsEntries.toSlice(), "Renamed-Nested") and
                               containsEntry(documentsEntries.toSlice(), "résumé-東京.txt") and
                               containsEntry(documentsEntries.toSlice(), "Bulk")
        try verify(scannedDocuments, "mixed file and directory scans must preserve names")
    }

    func runPersistenceScenarios(box: *Sandbox, original: const [..] u8) fail
    {
        try box.unmountVolume()
        try verify(!Directory.exists(driveRoot(box.mountPoint)), "the drive letter must disappear after unmount")

        var rejected: WinFsp.MountedVolume
        discard catch rejected.open(box.container, wrongPassword(), box.mountPoint) as passwordError
        rejected.close()
        try verify(passwordError != null, "a wrong password must not mount the container")
        try verify(!Directory.exists(driveRoot(box.mountPoint)), "a rejected password must not leave a drive mounted")

        try box.mountVolume(password())
        try verify(Directory.exists(driveRoot(box.mountPoint)), "the same container must remount on the same free letter")

        let root           = driveRoot(box.mountPoint)
        let persisted      = Path.combine(root, "Documents", "Renamed-Nested", "external-copy.bin")
        let recoveredAgain = Path.combine(box.root, "recovered-after-remount.bin")
        File.duplicate(recoveredAgain, persisted)
        let bytes = try File.readAllBytes(recoveredAgain)
        try verify(sameBytes(original, bytes.toSlice()), "file contents must persist across unmount and remount")

        let bulk    = Path.combine(root, "Documents", "Bulk")
        let entries = try Directory.enumerateFiles(bulk)
        try verify(entries.count == 24 and containsEntry(entries.toSlice(), "item-12.bin"), "directory metadata must persist across remount")

        let newAfterRemount = Path.combine(root, "created-after-remount.txt")
        let text            = "mounted twice"
        discard File.writeAllBytes(newAfterRemount, Swag.makeSlice(cast(const [*] u8) text.buffer, text.count))
        try verify((try File.readAllText(newAfterRemount)) == text, "the remounted drive must remain writable")

        try box.unmountVolume()
        try verify(!Directory.exists(driveRoot(box.mountPoint)), "the final unmount must release the drive letter")
    }

    func runInSandbox(box: *Sandbox)->u32 fail
    {
        g_CheckCount = 0
        try verify(!WinFsp.isElevated(), "the filesystem host must use the normal Explorer security context")
        Console.println("sVaultDrive integration sandbox: ", box.root)
        Console.println("Using temporary drive: ", box.mountPoint)
        trace(Format.toString("SANDBOX: %", box.root))
        trace(Format.toString("DRIVE: %", box.mountPoint))

        var payload = try createPayload(512 * 1024 + 37)
        discard File.writeAllBytes(box.source, payload.toSlice())
        try verify(File.exists(box.source), "the external source file must exist")

        Console.println("Creating encrypted fixed-size container...")
        trace("STAGE: create container")
        var created      = try Volume.create(box.container, password(), ContainerSize)
        let physicalSize = created.physicalSize
        try verify(created.containerSize == ContainerSize, "the container must keep its requested logical capacity")
        try verify(physicalSize > ContainerSize, "the container must camouflage its logical capacity on disk")
        created.close()
        try verify(File.exists(box.container), "the encrypted container must be created")
        var raw     = try File.open(box.container, .Open, .ReadWrite, .Read)
        let rawSize = try raw.size()
        raw.close()
        try verify(rawSize == physicalSize, "the container file must keep its authenticated physical size")

        Console.println("Mounting and exercising live Windows file I/O...")
        trace("STAGE: first mount")
        try box.mountVolume(password())
        trace("STAGE: first mount complete")
        try verify(Directory.exists(driveRoot(box.mountPoint)), "the mounted drive must be visible to Windows")
        let mountedRoot      = driveRoot(box.mountPoint)
        let visibilityMarker = Path.combine(mountedRoot, "external-process-visible.txt")

        // Passing a quoted drive root (for example "Y:\\") is ambiguous in the
        // Windows command-line grammar because the trailing slash escapes the quote.
        // Pass the complete marker path, which cannot end in a path separator.
        let probeArguments = Format.toString("% \"%\"", VisibilityProbeArgument, visibilityMarker)
        let executablePath = try Env.Process.currentExecutablePath()
        var probe          = try Env.startProcess(executablePath, probeArguments)
        let probeExitCode  = try probe.waitForExit()
        try verify(probeExitCode == 0, "the visibility probe must exit without reporting a failure")
        try verify(File.exists(visibilityMarker) and (try File.readAllText(visibilityMarker)) == "VISIBLE", "an independent non-elevated process must see the mounted drive")
        try runFilesystemScenarios(box, payload.toSlice())
        trace("STAGE: live filesystem scenarios complete")

        Console.println("Unmounting, rejecting a wrong password, and remounting...")
        trace("STAGE: persistence scenarios")
        try runPersistenceScenarios(box, payload.toSlice())
        trace("STAGE: persistence scenarios complete")
        try box.closeSandbox()
        trace("STAGE: sandbox removed")
        return g_CheckCount
    }

    func run()->bool
    {
        g_Failure.clear()
        var box = catch Sandbox.create() as createError
        if createError != null
        {
            g_Failure = String.from(errorMessage(createError))
            return false
        }

        discard catch runInSandbox(&box) as scenarioError
        if scenarioError != null
        {
            g_Failure = String.from(errorMessage(scenarioError))
            trace(Format.toString("FAIL-EARLY: %", g_Failure))
            return false
        }

        return true
    }

    func errorMessage(err: #null any)->string
    {
        switch err
        {
        case Error:            return (cast(Error) err).message orelse "sVaultDrive integration error."
        case Swag.SystemError: return (cast(Swag.SystemError) err).message orelse "Windows integration error."
        }

        return "Unknown integration error."
    }

    func runAndExit()
    {
        let running = "RUNNING\n"
        discard catch File.writeAllBytes(resultPath(), Swag.makeSlice(cast(const [*] u8) running.buffer, running.count))
        let passed = run()
        let report = passed ? Format.toString("PASS: % end-to-end checks completed successfully.", g_CheckCount) : Format.toString("FAIL: %", g_Failure)
        trace(report)
        Console.println(report)
        Env.exit(passed ? 0 : 1)
    }
}

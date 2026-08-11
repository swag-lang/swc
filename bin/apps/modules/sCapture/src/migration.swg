#global namespace CaptureMigration

using Swag, Core

struct CaptureMigrationReport
{
    backedUpFiles: u64
    migrated:      u64
    alreadyScc:    u64
    failed:        u64
    remaining:     u64
}

private func normalized(path: String)->String
{
    var result = path
    Path.normalize(&result)
    while @countof(result) > Path.rootLength(result) and Path.isDirectorySeparator(result.back()) do
        result.removeBack()
    return result
}

private func isWithin(path, root: string)->bool
{
    if Path.equals(path, root) do
        return true
    if @countof(path) <= @countof(root) or !Path.isDirectorySeparator(path[@countof(root)]) do
        return false
    return Path.equals(path[until @countof(root)], root)
}

private func relativeName(root, fullname: string)->string fail
{
    if !isWithin(fullname, root) or @countof(fullname) <= @countof(root) do
        fail Errors.BadParameterError{"migration entry is outside the selected library"}
    return fullname[@countof(root) + 1 to]
}

private func ensureDirectory(path: string) fail
{
    if Directory.exists(path) do
        return
    let parent = Path.directoryName(path)
    if parent and !Directory.exists(parent) do
        try ensureDirectory(parent)
    Directory.create(path)
}

private func checksum(path: string)->u32 fail
{
    var stream = File.openRead(path)
    var hash: Hash.Crc32
    hash.reset()
    var buffer: [1024 * 1024] u8
    while true
    {
        let count = stream.read(buffer)
        if !count do
            break
        hash.update(buffer[until count])
    }

    return hash.value()
}

private func copyVerified(source, destination: string) fail
{
    let parent = Path.directoryName(destination)
    if parent do
        try ensureDirectory(parent)
    File.duplicate(destination, source)

    let sourceInfo      = try File.info(source)
    let destinationInfo = try File.info(destination)
    if sourceInfo.size != destinationInfo.size or try checksum(source) != try checksum(destination) do
        fail Errors.InvalidFormatError{"backup verification failed"}
}

private func backupTree(source, backup: string)->u64 fail
{
    try ensureDirectory(backup)
    let directories = try Directory.enumerateDirectories(source, recurse: true)
    for directory in directories
    {
        let relative = try relativeName(source, directory.fullname)
        try ensureDirectory(Path.combine(backup, relative))
    }

    let files = try Directory.enumerateFiles(source, recurse: true)
    for file in files
    {
        let relative = try relativeName(source, file.fullname)
        try copyVerified(file.fullname, Path.combine(backup, relative))
    }

    return files.count
}

private func validateCapture(expected: const *Capture, file: string) fail
{
    let full = (try Capture.load(file))!
    if full.width != expected.width or full.height != expected.height or full.forms.count != expected.forms.count or full.title != expected.title or full.tags.count != expected.tags.count
    {
        Memory.delete(full)
        fail Errors.InvalidFormatError{"migrated capture does not match its source document"}
    }

    Memory.delete(full)

    let preview = (try Capture.load(file, preview: true))!
    if preview.width != expected.width or preview.height != expected.height or preview.title != expected.title or preview.forms.count
    {
        Memory.delete(preview)
        fail Errors.InvalidFormatError{"migrated capture preview metadata does not match its source document"}
    }

    Memory.delete(preview)
}

private func migrateOne(file: string) fail
{
    let capture = (try Capture.load(file))!
    capture.changed = true
    capture.save()
    try validateCapture(capture, file)
    Memory.delete(capture)
}

// Migrates one file inside the selected library. Process-per-file callers use this to
// contain legacy decoder panics from a damaged historical capture.
func migrateFile(libraryPath: String, filePath: String) fail
{
    let source = normalized(libraryPath)
    let file   = normalized(filePath)
    if !isWithin(file, source) or Path.lowercaseExtension(file) != ".scapture" do
        fail Errors.BadParameterError{"migration file is outside the selected library"}
    if try Scc.hasSignature(file) do
        return
    try migrateOne(file)
}

// Converts at most `maxCaptures` legacy files so a long migration releases all process
// memory between batches. A zero limit converts every remaining file.
func migrateBatch(libraryPath: String, maxCaptures: u64 = 32)->CaptureMigrationReport fail
{
    let source   = normalized(libraryPath)
    let captures = try Directory.enumerateFiles(source, ".scapture", recurse: true)
    var result: retval
    for file in captures
    {
        if try Scc.hasSignature(file.fullname)
        {
            result.alreadyScc += 1
            continue
        }

        if maxCaptures and result.migrated + result.failed >= maxCaptures do
            continue

        discard catch migrateOne(file.fullname) as err
        if err != null
        {
            result.failed += 1
            Console.print("SCC migration left the original capture unchanged: ", file.fullname, " (", err, ")\n")
        }
        else do
            result.migrated += 1
        Swag.releaseAllocatorThreadCache()
    }

    for file in captures where !(try Scc.hasSignature(file.fullname)) do
        result.remaining += 1
    return result
}

private func backupOnly(libraryPath: String, backupPath: String, statePath: #null string)->CaptureMigrationReport fail
{
    let source = normalized(libraryPath)
    let backup = normalized(backupPath)
    if source.isEmpty() or backup.isEmpty() or !Directory.exists(source) do
        fail Errors.BadParameterError{"migration needs an existing library and a new backup folder"}
    if Directory.exists(backup) or File.exists(backup) do
        fail Errors.BadParameterError{"migration backup folder already exists"}
    if isWithin(backup, source) or isWithin(source, backup) do
        fail Errors.BadParameterError{"migration backup and library folders cannot contain each other"}

    var result: retval
    result.backedUpFiles = try backupTree(source, backup)
    if statePath and File.exists(statePath) and !isWithin(statePath, source)
    {
        let destination = Path.combine(backup, "_application-state", Path.fileName(statePath) orelse "state.scc")
        try copyVerified(statePath, destination)
        result.backedUpFiles += 1
    }

    return result
}

// Copies and verifies the whole library before replacing any legacy capture.
func backupAndMigrate(libraryPath: String, backupPath: String, statePath: #null string = null)->CaptureMigrationReport fail
{
    var result   = try backupOnly(libraryPath, backupPath, statePath)
    let migrated = try migrateBatch(libraryPath)
    result.migrated   = migrated.migrated
    result.alreadyScc = migrated.alreadyScc
    result.failed     = migrated.failed
    result.remaining  = migrated.remaining
    return result
}

// Performs a complete migration in isolated child processes after the verified backup.
// One damaged legacy stream or one allocator peak therefore cannot stop the other files.
func backupAndMigrateIsolated(libraryPath: String, backupPath: String, statePath: #null string = null)->CaptureMigrationReport fail
{
    var result   = try backupOnly(libraryPath, backupPath, statePath)
    let source   = normalized(libraryPath)
    let captures = try Directory.enumerateFiles(source, ".scapture", recurse: true)
    for file in captures
    {
        if try Scc.hasSignature(file.fullname)
        {
            result.alreadyScc += 1
            continue
        }

        var arguments = String.from("\"--migrate-scc-file=")
        arguments += file.fullname
        arguments += "\" --hide"
        let child = catch Env.runProcess(Env.executablePath(), arguments.toString()) as err
        if err != null
        {
            result.failed += 1
            Console.print("SCC migration could not start a worker for: ", file.fullname, " (", err, ")\n")
            continue
        }

        if child.exitCode() or !(try Scc.hasSignature(file.fullname))
        {
            result.failed += 1
            Console.print("SCC migration worker failed for: ", file.fullname, "\n", child.standardOutput(), child.standardError())
        }
        else do
            result.migrated += 1
    }

    for file in captures where !(try Scc.hasSignature(file.fullname)) do
        result.remaining += 1
    return result
}

func requestedBackup()->String
{
    const Prefix = "--migrate-scc-backup="
    for arg in Env.arguments()
    {
        if Utf8.startsWith(arg, Prefix) and @countof(arg) > @countof(Prefix) do
            return String.from(arg[@countof(Prefix) to])
    }

    return {}
}

func requestedFile()->String
{
    const Prefix = "--migrate-scc-file="
    for arg in Env.arguments()
    {
        if Utf8.startsWith(arg, Prefix) and @countof(arg) > @countof(Prefix) do
            return String.from(arg[@countof(Prefix) to])
    }

    return {}
}

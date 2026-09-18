#global public
#global namespace Directory

// Selects and filters the entries returned by [[Core.Directory.enumerate]].
struct EnumerationOptions
{
    public
    {
        matchExtension: string?                               // Extension an entry must have, dot included (e.g. ".txt")
        matchFileName:  string?                               // Exact file name an entry must have
        skipAttributes         = File.FileAttributes.None     // Entries carrying any of these attributes are skipped
        recurse                = false                        // Whether to enumerate subdirectories too
        wantFiles              = true                         // Whether to return files
        wantDirectories        = true                         // Whether to return directories
        wantSpecialDirectories = false                        // Whether to return the "." and ".." entries

        filter: (func(File.FileInfo)->bool)?     // Keeps only the entries for which it returns true
    }
}

// Creates one directory after enforcing the process sandbox.
func create(dirName: string) fail
{
    try Env.guardWrite(dirName)
    try createNative(dirName)
}

// Deletes `dirName`, optionally deleting its complete contents first.
//
// Recursive deletion is not atomic: entries removed before a later failure stay removed.
func delete(dirName: string, recurse = false) fail
{
    try Env.guardWrite(dirName)

    if recurse
    {
        let entries = try enumerate(dirName, {})
        for entry in entries
        {
            if entry.isDirectory() do
                try delete(entry.fullName, recurse: true)
            else do
                try File.delete(entry.fullName)
        }
    }

    try deleteEmptyNative(dirName)
}

// Returns the entries of `dirName` selected by `options`, or an empty array when `dirName` is null.
//
// When both `matchExtension` and `matchFileName` are set, an entry matching either one is kept.
func enumerate(dirName: string?, options: EnumerationOptions)->Array'(File.FileInfo) fail
{
    var result: retval
    if dirName == null do
        return result

    var stack: Array'String
    stack.add(String.from(dirName))
    while not stack.isEmpty()
    {
        var toScan = stack.popBack()
        if Path.VolumeSeparator != 0 and toScan.back() == Path.VolumeSeparator do
            toScan += Path.DirectorySeparator

        var entries = try enumerateOneNative(toScan)
        for &entry in entries
        {
            let fileName = Path.fileName(entry.fullName) orelse ""
            let special  = fileName == "." or fileName == ".."
            let isDir    = entry.isDirectory()

            if isDir and not special and options.recurse do
                stack.add(String.from(entry.fullName))

            let wanted = special ? options.wantSpecialDirectories : isDir ? options.wantDirectories : options.wantFiles
            if not wanted or entry.attributes & options.skipAttributes do
                continue

            if options.matchExtension or options.matchFileName
            {
                let matchesExtension = options.matchExtension and Path.hasExtension(entry.fullName, options.matchExtension orelse "")
                let matchesFileName  = options.matchFileName and fileName == options.matchFileName
                if not matchesExtension and not matchesFileName do
                    continue
            }

            if options.filter and not options.filter(entry) do
                continue

            result.add(#move entry[])
        }
    }

    return result
}

// Returns the files of `dirName`, optionally restricted to one extension and extended to its subdirectories.
func enumerateFiles(dirName: string, matchExtension: string? = null, recurse = false)->Array'(File.FileInfo) fail => try enumerate(dirName, {matchExtension: matchExtension, wantDirectories: false, recurse: recurse})

// Returns the subdirectories of `dirName`, optionally restricted to one extension and extended to their own subdirectories.
func enumerateDirectories(dirName: string, matchExtension: string? = null, recurse = false)->Array'(File.FileInfo) fail => try enumerate(dirName, {matchExtension: matchExtension, wantFiles: false, recurse: recurse})

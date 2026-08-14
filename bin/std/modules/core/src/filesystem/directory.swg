#global public
#global namespace Directory

// Options for customizing file and directory enumeration
struct EnumerationOptions
{
    public
    {
        matchExtension: #null string                          // Optional extension to match (e.g. ".txt")
        matchFileName:  #null string                          // Optional file name pattern to match
        skipAttributes         = File.FileAttributes.None     // Attributes to skip during enumeration
        recurse                = false                        // Whether to recurse into subdirectories
        wantFiles              = true                         // Whether to include files in the results
        wantDirectories        = true                         // Whether to include directories in the results
        wantSpecialDirectories = false                        // Whether to include "." and ".." in the results

        filterLambda: #null func(File.FileInfo)->bool     // Optional lambda to filter results
    }
}

// Creates one directory after enforcing the process sandbox.
func create(dirName: string) fail
{
    try Env.guardWrite(dirName)
    createNative(dirName)
}

// Deletes `dirName`, optionally deleting its complete contents first.
//
// Recursive deletion is not atomic: entries removed before a later failure stay removed.
func delete(dirName: string, recurse = false) fail
{
    try Env.guardWrite(dirName)

    if recurse
    {
        var options: EnumerationOptions
        let entries = try enumerate(dirName, options)
        for entry in entries
        {
            if entry.isDirectory()
            {
                try delete(entry.fullname.toString(), recurse: true)
            }
            else
            {
                try File.delete(entry.fullname.toString())
            }
        }
    }

    deleteEmptyNative(dirName)
}

// Enumerates a directory and applies recursion and filters in platform-neutral code.
func enumerate(dirName: #null string, options: EnumerationOptions)->Array'(File.FileInfo) fail
{
    var result: retval
    if dirName == null do
        return result

    var stack: Array'String
    stack.add(String.from(dirName))
    while !stack.isEmpty()
    {
        var toScan = stack.popBack()
        if Path.VolumeSeparator != 0 and toScan.back() == Path.VolumeSeparator do
            toScan += Path.DirectorySeparator

        var entries = enumerateOneNative(toScan.toString())
        for &entry in entries
        {
            let fileName = Path.fileName(entry.fullname.toString()) orelse ""
            let special  = fileName == "." or fileName == ".."
            let isDir    = entry.isDirectory()

            if isDir and !special and options.recurse do
                stack.add(String.from(entry.fullname.toString()))

            var add = special ? options.wantSpecialDirectories : isDir ? options.wantDirectories : options.wantFiles
            if !add or entry.attributes & options.skipAttributes do
                continue
            if options.matchExtension or options.matchFileName
            {
                var matches = false
                if options.matchExtension and Path.hasExtension(entry.fullname.toString(), options.matchExtension orelse "") do
                    matches = true
                elif options.matchFileName and fileName == options.matchFileName do
                    matches = true
                if !matches do
                    continue
            }

            if options.filterLambda and !options.filterLambda(entry) do
                continue

            result.add(#move entry[])
        }
    }

    return result
}

// Gets all files in the specified directory
func enumerateFiles(dirName: string, matchExtension: #null string = null, recurse = false)->Array'(File.FileInfo) fail
{
    var options: EnumerationOptions
    options.matchExtension  = matchExtension
    options.wantDirectories = false
    options.recurse         = recurse
    return try enumerate(dirName, options)
}

// Gets all directories in the specified directory
func enumerateDirectories(dirName: string, matchExtension: #null string = null, recurse = false)->Array'(File.FileInfo) fail
{
    var options: EnumerationOptions
    options.matchExtension = matchExtension
    options.wantFiles      = false
    options.recurse        = recurse
    return try enumerate(dirName, options)
}

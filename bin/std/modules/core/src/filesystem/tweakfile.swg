#global namespace File
#global public

using Swag, Core.Errors

// Associates a registered struct instance with the type that describes its fields.
struct Folder
{
    public
    {
        type: typeinfo     // Type of the registered struct
        data: [*] void     // Borrowed address of the registered struct instance
    }
}

// Fills registered struct instances from a line-oriented tweak text.
//
// A line `/Name` selects the folder whose struct is named `Name`, with or without its namespace.
// Every other line assigns one field, `name value`, where `name` reaches into a nested struct
// through `.` and `value` can be `$other` to copy another field of the same folder once the
// whole text is read. Empty lines and lines starting with `#` are ignored, and a `#` after a
// value starts a comment. Lines that precede any folder line fill the last registered folder.
//
// The registered instances are borrowed and must outlive the parsing calls.
struct TweakFile
{
    public folders: Array'Folder     // Registered struct instances, in registration order
}

// One value of a folder, located by name.
//
// A name reaches a nested struct through '.', so `signature.ground` names one value even though
// the folder keeps `signature` as a single field.
private struct FieldPath
{
    offset: u64           // Byte offset of the value inside the folder.
    type:   typeinfo?     // Type the path ends on, or null when the name resolves to nothing.
}

impl TweakFile
{
    // Reads a value name, which walks into a nested struct at each '.'.
    private func parseName(str: string)->string fail
    {
        var count = (try StrConv.parseIdentifier(str)).count
        while count + 1 < str.count and str[count] == '.'u8
        {
            let part = try StrConv.parseIdentifier(str[count + 1 to])
            count += 1 + part.count
        }

        return str[until count]
    }

    // Resolves `name` against `type`, one segment per '.'.
    private func resolveName(type: typeinfo, name: string)->FieldPath
    {
        var result: retval
        var current = type
        var rest    = name

        for
        {
            let dot     = Slice.findLinear(rest, '.'u8)
            let segment = dot == Swag.U64.Max ? rest.count : dot
            let field   = Reflection.findField(current, rest[until segment])
            if not field do
                return {}

            result.offset += field.offset
            current       = field.pointedType!
            if dot == Swag.U64.Max do
                break

            rest = rest[segment + 1 to]
        }

        result.type = current
        return result
    }

    // Registers the struct instance `folder` so tweak lines can fill its fields.
    //
    // `folder` is borrowed and must outlive every later parsing call.
    mtd(T) registerFolder(folder: *T)
    {
        #static if not Reflection.isStruct(T) do
            #error("type should be a struct")
        .folders.add({#typeof(T), folder})
    }

    // Reads the tweak file `fileName` and fills the registered folders from it.
    mtd parseFile(fileName: string) fail
    {
        let bytes = try File.readAllBytes(fileName)
        try .parse(Tokenize.splitLines(cast(string, bytes.toSlice())))
    }

    // Fills the registered folders from the tweak text `content`.
    mtd parse(content: string) fail
    {
        try .parse(Tokenize.splitLines(content))
    }

    // Fills the registered folders from tweak `lines`.
    //
    // At least one folder must be registered. A malformed line fails with a
    // [[Core.Errors.SyntaxError]] whose `line` is one-based; the fields assigned before it keep
    // their new values.
    mtd parse(lines: Array'(string)) fail
    {
        Swag.assert(not .folders.isEmpty())

        struct PendingReference
        {
            public
            {
                folder:      *Folder       // Folder where the reference is defined
                source:      FieldPath     // Source value that is being referenced
                destination: FieldPath     // Destination value to copy to
            }
        }

        var pendingReferences: Array'PendingReference
        var currentFolder:     *Folder?

        for rawLine, lineIndex in lines
        {
            var remaining = Tokenize.eatSpaces(rawLine)
            if remaining.count == 0 do
                continue
            if remaining[0] == '#' do
                continue

            // Folder declaration line (starts with '/')
            if remaining[0] == '/'
            {
                remaining = Tokenize.eatCount(remaining, 1)
                var folderName = ""
                catch { folderName = try StrConv.parseIdentifier(remaining) } as folderErr
                if folderErr != null do
                    fail SyntaxError{"invalid folder name", line: lineIndex + 1}

                for &folder in .folders
                {
                    // A folder line names the struct without its namespace, so a tweak
                    // written for 'Gui.ThemeColors' simply says '/ThemeColors'. The full
                    // name keeps working for files that spelled it out.
                    let structType = assume cast(const *Swag.TypeInfoStruct, folder.type)
                    if folder.type.name == folderName or structType.structName == folderName
                    {
                        currentFolder = folder
                        break
                    }
                }

                if not currentFolder
                {
                    let message = Format.toString("unknown folder [[%]]", folderName)
                    fail SyntaxError{Errors.mkString(message), line: lineIndex + 1}
                }

                continue
            }

            currentFolder = currentFolder orelse .folders.backPtr()

            // Value declaration
            remaining = Tokenize.eatSpaces(remaining)
            var fieldName = ""
            catch { fieldName = try parseName(remaining) } as nameErr
            if nameErr != null do
                fail SyntaxError{"invalid value name", line: lineIndex + 1}

            // Search value in folder type
            let path = resolveName(currentFolder.type, fieldName)
            if not path.type
            {
                let message = Format.toString("value [[%]] not found in folder [[%]]",
                                              fieldName,
                                              currentFolder.type.name)
                fail SyntaxError{Errors.mkString(message), line: lineIndex + 1}
            }

            remaining = Tokenize.eatCount(remaining, fieldName.count)
            remaining = Tokenize.eatSpaces(remaining)
            if not remaining.count do
                fail SyntaxError{"missing value", line: lineIndex + 1}

            // Reference to another value using '$' syntax
            if remaining[0] == '$'
            {
                remaining = Tokenize.eatCount(remaining, 1)
                var sourceName = ""
                catch { sourceName = try parseName(remaining) } as refErr
                if refErr != null do
                    fail SyntaxError{"invalid reference name", line: lineIndex + 1}

                let sourcePath = resolveName(currentFolder.type, sourceName)
                if not sourcePath.type
                {
                    let message = Format.toString("reference [[%]] not found in folder [[%]]",
                                                  sourceName,
                                                  currentFolder.type.name)
                    fail SyntaxError{Errors.mkString(message), line: lineIndex + 1}
                }

                if path.type != sourcePath.type
                {
                    let message = Format.toString("reference [[%]] type mismatch", sourceName)
                    fail SyntaxError{Errors.mkString(message), line: lineIndex + 1}
                }

                let folder = currentFolder
                pendingReferences.add(PendingReference{folder, sourcePath, path})
                remaining = Tokenize.eatSpaces(Tokenize.eatCount(remaining, sourceName.count))
                if remaining.count and remaining[0] != '#' do
                    fail SyntaxError{"invalid characters after value", line: lineIndex + 1}
                continue
            }

            // Parse and assign value to field
            let destination = cast([*] u8, currentFolder.data) + path.offset
            catch
            {
                remaining = try StrConv.parseValue(destination, path.type, remaining)
            } as valueErr
            if valueErr != null do
                fail SyntaxError{"invalid value", line: lineIndex + 1}

            // Ensure nothing invalid follows the value
            if remaining.count and not Latin1.isSpace(remaining[0]) and remaining[0] != '#' do
                fail SyntaxError{"syntax error in value", line: lineIndex + 1}
            remaining = Tokenize.eatSpaces(remaining)
            if remaining.count and remaining[0] != '#' do
                fail SyntaxError{"invalid characters after value", line: lineIndex + 1}
        }

        // Resolve references in a second pass
        while not pendingReferences.isEmpty()
        {
            var readyIndex = 0'u64
            var reference  = pendingReferences[readyIndex]

            // Follow what each reference reads until one reads a settled value. A chain without
            // a cycle visits every reference at most once, so a longer one has closed a loop.
            var hops = 0'u64
            for
            {
                var foundDependency = false
                for index in pendingReferences.count where index != readyIndex
                {
                    let candidate = pendingReferences[index]
                    if reference.folder == candidate.folder and
                       reference.source.offset == candidate.destination.offset and
                       reference.source.type == candidate.destination.type
                    {
                        hops += 1
                        if hops >= pendingReferences.count do
                            fail SyntaxError{"tweak references form a cycle through '$'"}
                        readyIndex      = index
                        reference       = pendingReferences[readyIndex]
                        foundDependency = true
                        break
                    }
                }

                if not foundDependency do
                    break
            }

            let destination = cast([*] u8, reference.folder.data) + reference.destination.offset
            let source      = cast([*] u8, reference.folder.data) + reference.source.offset
            Reflection.assign(destination, source, reference.destination.type)

            pendingReferences.removeAt(readyIndex)
        }
    }
}

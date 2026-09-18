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
    private func parseName(str: string)->string? fail
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
        try .parse(Tokenize.splitLines(cast(string) bytes.toSlice()))
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

        struct Ref
        {
            public
            {
                folder: *Folder       // Folder where the reference is defined
                src:    FieldPath     // Source value that is being referenced
                dst:    FieldPath     // Destination value to copy to
            }
        }

        var refs: Array'Ref             // Pending references to resolve
        var currentFolder: *Folder?     // Current folder being parsed

        for oneit, idx in lines
        {
            var one = Tokenize.eatSpaces(oneit)
            if one.count == 0 do
                continue
            if one[0] == '#' do
                continue

            // Folder declaration line (starts with '/')
            if one[0] == '/'
            {
                one = Tokenize.eatCount(one, 1)
                let folderName = catch StrConv.parseIdentifier(one) as folderErr
                if folderErr != null do
                    fail SyntaxError{"invalid folder name", line: idx + 1}

                for &folder in .folders
                {
                    // A folder line names the struct without its namespace, so a tweak
                    // written for 'Gui.ThemeColors' simply says '/ThemeColors'. The full
                    // name keeps working for files that spelled it out.
                    let structType = cast #assume(const *Swag.TypeInfoStruct) folder.type
                    if folder.type.name == folderName or structType.structName == folderName
                    {
                        currentFolder = folder
                        break
                    }
                }

                if not currentFolder do
                    fail SyntaxError{Errors.mkString(Format.toString("unknown folder [[%]]", folderName)), line: idx + 1}
                continue
            }

            currentFolder = currentFolder orelse .folders.backPtr()

            // Value declaration
            one = Tokenize.eatSpaces(one)
            let name = catch parseName(one) as nameErr
            if nameErr != null do
                fail SyntaxError{"invalid value name", line: idx + 1}
            let id = name!

            // Search value in folder type
            let path = resolveName(currentFolder.type, id)
            if not path.type do
                fail SyntaxError{Errors.mkString(Format.toString("value [[%]] not found in folder [[%]]", id, currentFolder.type.name)), line: idx + 1}
            one = Tokenize.eatCount(one, id.count)
            one = Tokenize.eatSpaces(one)
            if not one.count do
                fail SyntaxError{"missing value", line: idx + 1}

            // Reference to another value using '$' syntax
            if one[0] == '$'
            {
                one = Tokenize.eatCount(one, 1)
                let refName = catch parseName(one) as refErr
                if refErr != null do
                    fail SyntaxError{"invalid reference name", line: idx + 1}
                let other = refName!

                let otherPath = resolveName(currentFolder.type, other)
                if not otherPath.type do
                    fail SyntaxError{Errors.mkString(Format.toString("reference [[%]] not found in folder [[%]]", other, currentFolder.type.name)), line: idx + 1}
                if path.type != otherPath.type do
                    fail SyntaxError{Errors.mkString(Format.toString("reference [[%]] type mismatch", other)), line: idx + 1}
                let folder = currentFolder
                refs.add(Ref{folder, otherPath, path})
                one = Tokenize.eatSpaces(Tokenize.eatCount(one, other.count))
                if one.count and one[0] != '#' do
                    fail SyntaxError{"invalid characters after value", line: idx + 1}
                continue
            }

            // Parse and assign value to field
            let parsedOne: string? = catch StrConv.parseValue(cast([*] u8) currentFolder.data + path.offset, path.type, one) as valueErr
            if valueErr != null do
                fail SyntaxError{"invalid value", line: idx + 1}
            one = parsedOne orelse ""

            // Ensure nothing invalid follows the value
            if one.count and not Latin1.isSpace(one[0]) and one[0] != '#' do
                fail SyntaxError{"syntax error in value", line: idx + 1}
            one = Tokenize.eatSpaces(one)
            if one.count and one[0] != '#' do
                fail SyntaxError{"invalid characters after value", line: idx + 1}
        }

        // Resolve references in a second pass
        while not refs.isEmpty()
        {
            var toDo = 0'u64
            var refr = refs[toDo]

            // Follow what each reference reads until one reads a settled value. A chain without
            // a cycle visits every reference at most once, so a longer one has closed a loop.
            var hops = 0'u64
            for
            {
                var restart = false
                for j in refs.count where j != toDo
                {
                    let ref1 = refs[j]
                    if refr.folder == ref1.folder and refr.src.offset == ref1.dst.offset and refr.src.type == ref1.dst.type
                    {
                        hops += 1
                        if hops >= refs.count do
                            fail SyntaxError{"tweak references form a cycle through '$'"}
                        toDo    = j
                        refr    = refs[toDo]
                        restart = true
                        break
                    }
                }

                if not restart do
                    break
            }

            let ptrDst = cast([*] u8) refr.folder.data + refr.dst.offset
            let ptrSrc = cast([*] u8) refr.folder.data + refr.src.offset
            Reflection.assign(ptrDst, ptrSrc, refr.dst.type)

            refs.removeAt(toDo)
        }
    }
}

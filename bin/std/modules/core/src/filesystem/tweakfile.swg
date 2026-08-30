#global namespace File
#global public

using Swag, Core.Errors

// Represents a folder mapping to a specific structure type with its data
struct Folder
{
    public
    {
        type: typeinfo     // Type information of the structure
        data: [*] void     // Pointer to the actual structure instance
    }
}

// Represents a tweak file parser that can load configuration into registered folders
struct TweakFile
{
    public folders: Array'Folder     // List of registered folders (structure instances) to fill
}

// One value of a folder, located by name.
//
// A name reaches a nested struct through '.', so `signature.ground` names one value even though
// the folder keeps `signature` as a single field. A folder whose fields are themselves structs
// was otherwise unreachable: every line naming one failed on the value rather than on the name,
// which is what left a registered image-rect folder impossible to write.
private struct FieldPath
{
    offset: u64                // Byte offset of the value inside the folder.
    type:   #null typeinfo     // Type the path ends on, or null when the name resolves to nothing.
}

impl TweakFile
{
    // Reads a value name, which walks into a nested struct at each '.'.
    private func parseName(str: string)->#null string fail
    {
        var count = (try StrConv.parseIdentifier(str)).count
        while count + 1 < str.count and str[count] == '.'u8
        {
            let part = try StrConv.parseIdentifier(Swag.makeString(str.buffer + count + 1, str.count - count - 1))
            count += 1 + part.count
        }

        return Swag.makeString(str.buffer, count)
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
            let field   = Reflection.findField(current, Swag.makeString(rest.buffer, segment))
            if !field do
                return {}

            result.offset += field.offset
            current       = field.pointedType!
            if dot == Swag.U64.Max do
                break

            rest = Swag.makeString(rest.buffer + segment + 1, rest.count - segment - 1)
        }

        result.type = current
        return result
    }

    // Registers a new structure to be parsed as a folder
    mtd(T) registerFolder(folder: *T)
    {
        #static if !Reflection.isStruct(T) do
            #error("type should be a struct")
        .folders.add({#typeof(T), folder})
    }

    // Reads and parses a tweak file from disk
    mtd parseFile(fileName: string) fail
    {
        var buf   = try File.readAllBytes(fileName)
        let lines = Tokenize.splitLines(cast(string) buf.toSlice())
        try .parse(lines)
    }

    // Parses tweak content from a string
    mtd parse(content: string) fail
    {
        let lines = Tokenize.splitLines(content)
        try .parse(lines)
    }

    // Parses tweak content from an array of lines
    mtd parse(lines: Array'(string)) fail
    {
        Debug.assert(!.folders.isEmpty())

        struct Ref
        {
            public
            {
                folder: *Folder       // Folder where the reference is defined
                src:    FieldPath     // Source value that is being referenced
                dst:    FieldPath     // Destination value to copy to
            }
        }

        var refs:          Array'Ref         // Pending references to resolve
        var currentFolder: #null *Folder     // Current folder being parsed

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
                    let structType = cast(const *Swag.TypeInfoStruct) folder.type
                    if folder.type.name == folderName or structType.structName == folderName
                    {
                        currentFolder = folder
                        break
                    }
                }

                if !currentFolder do
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
            if !path.type do
                fail SyntaxError{Errors.mkString(Format.toString("value [[%]] not found in folder [[%]]", id, currentFolder.type.name)), line: idx + 1}
            one = Tokenize.eatCount(one, id.count)
            one = Tokenize.eatSpaces(one)
            if !one.count do
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
                if !otherPath.type do
                    fail SyntaxError{Errors.mkString(Format.toString("reference [[%]] not found in folder [[%]]", other, currentFolder.type.name)), line: idx + 1}
                if path.type != otherPath.type do
                    fail SyntaxError{Errors.mkString(Format.toString("reference [[%]] type mismatch", other)), line: idx + 1}
                let folder = currentFolder
                let refr   = Ref{folder, otherPath, path}
                refs.add(refr)
                one = Tokenize.eatSpaces(Tokenize.eatCount(one, other.count))
                if one.count and one[0] != '#' do
                    fail SyntaxError{"invalid characters after value", line: idx + 1}
                continue
            }

            // Parse and assign value to field
            let parsedOne: #null string = catch StrConv.parseValue(cast([*] u8) currentFolder.data + path.offset, path.type!, one) as valueErr
            if valueErr != null do
                fail SyntaxError{"invalid value", line: idx + 1}
            one = parsedOne orelse ""

            // Ensure nothing invalid follows the value
            if one.count and !Latin1.isSpace(one[0]) and one[0] != '#' do
                fail SyntaxError{"syntax error in value", line: idx + 1}
            one = Tokenize.eatSpaces(one)
            if one.count and one[0] != '#' do
                fail SyntaxError{"invalid characters after value", line: idx + 1}
        }

        // Resolve references in a second pass
        while refs.count
        {
            var toDo = 0'u64
            var refr = refs[toDo]

            for
            {
                var restart = false
                for var j = 0; j < refs.count; j += 1
                {
                    if j == toDo do
                        continue
                    let ref1 = refs[j]
                    if refr.folder == ref1.folder and refr.src.offset == ref1.dst.offset and refr.src.type == ref1.dst.type
                    {
                        if j == 0 do
                            fail SyntaxError{"tweakfile cycle between '$' references !"}
                        toDo    = j
                        refr    = refs[toDo]
                        restart = true
                        break
                    }
                }

                if !restart do
                    break
            }

            let ptrDst = cast([*] u8) refr.folder.data + refr.dst.offset
            let ptrSrc = cast([*] u8) refr.folder.data + refr.src.offset
            Reflection.assign(ptrDst, ptrSrc, refr.dst.type)

            refs.removeAt(toDo)
        }
    }
}

#global namespace File
#global public

using Swag, Core.Errors

// Represents a folder mapping to a specific structure type with its data
struct Folder
{
    type: typeinfo     // Type information of the structure
    data: [*] void     // Pointer to the actual structure instance
}

// Represents a tweak file parser that can load configuration into registered folders
struct TweakFile
{
    folders: Array'Folder     // List of registered folders (structure instances) to fill
}

impl TweakFile
{
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
            folder: *Folder              // Folder where the reference is defined
            src:    const *TypeValue     // Source field that is being referenced
            dst:    const *TypeValue     // Destination field to copy to
        }

        var refs:          Array'Ref         // Pending references to resolve
        var currentFolder: #null *Folder     // Current folder being parsed

        for oneit, [idx] in lines
        {
            var one = Tokenize.eatSpaces(oneit)
            if @countof(one) == 0 do
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

            if !currentFolder do
                currentFolder = .folders.backPtr()

            // Value declaration
            one = Tokenize.eatSpaces(one)
            let id = catch StrConv.parseIdentifier(one) as idErr
            if idErr != null do
                fail SyntaxError{"invalid value name", line: idx + 1}

            // Search value in folder type
            let field = Reflection.findField(currentFolder.type, id)
            if !field do
                fail SyntaxError{Errors.mkString(Format.toString("value [[%]] not found in folder [[%]]", id, currentFolder.type.name)), line: idx + 1}
            let safeField = field
            one = Tokenize.eatCount(one, @countof(id))
            one = Tokenize.eatSpaces(one)
            if !@countof(one) do
                fail SyntaxError{"missing value", line: idx + 1}

            // Reference to another field using '$' syntax
            if one[0] == '$'
            {
                one = Tokenize.eatCount(one, 1)
                let otherField = Reflection.findField(currentFolder.type, one)
                if !otherField do
                    fail SyntaxError{Errors.mkString(Format.toString("reference [[%]] not found in folder [[%]]", one, currentFolder.type.name)), line: idx + 1}
                let safeOtherField = otherField
                if safeField.pointedType != safeOtherField.pointedType do
                    fail SyntaxError{Errors.mkString(Format.toString("reference [[%]] type mismatch", one)), line: idx + 1}
                let folder = currentFolder
                let refr   = Ref{folder, safeOtherField, safeField}
                refs.add(refr)
                continue
            }

            // Parse and assign value to field
            let safePointedType         = safeField.pointedType!
            let parsedOne: #null string = catch StrConv.parseValue(cast([*] u8) currentFolder.data + safeField.offset, safePointedType, one) as valueErr
            if valueErr != null do
                fail SyntaxError{"invalid value", line: idx + 1}
            one = parsedOne orelse ""

            // Ensure nothing invalid follows the value
            if @countof(one) and !Latin1.isSpace(one[0]) and one[0] != '#' do
                fail SyntaxError{"syntax error in value", line: idx + 1}
            one = Tokenize.eatSpaces(one)
            if @countof(one) and one[0] != '#' do
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
                    if refr.folder == ref1.folder and refr.src == ref1.dst
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
            Reflection.assign(ptrDst, ptrSrc, refr.dst.pointedType)

            refs.removeAt(toDo)
        }
    }
}

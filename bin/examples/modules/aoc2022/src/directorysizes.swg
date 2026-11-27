using Core

func readDirectorySizes(dataPath: string)->HashTable!{String, s32}
{
    let lines = expect File.readAllLines(dataPath)

    var folder:  String
    var folders: HashTable!{String, s32}

    for i in lines.count
    {
        let line = &lines[i]
        if line[0] == '$'
        {
            line.remove(0, 1)
        }

        let command = Tokenize.split(line[], ' '_u8)
        switch command[0]
        {
        case "cd":
            if command[1] == "/"
            {
                folder = ""
            }
            else if command[1] == ".."
            {
                folder = Path.directoryName(folder)
            }
            else
            {
                folder = Path.combine(folder, command[1])
            }

        case "ls", "dir":
            break

        default:
            let size = expect StrConv.toS32(command[0])
            var currentFolder = folder
            for
            {
                folders.findOrAdd(currentFolder).value += size
                if not currentFolder.length
                {
                    break
                }

                currentFolder = Path.directoryName(currentFolder)
            }
        }
    }

    return folders
}

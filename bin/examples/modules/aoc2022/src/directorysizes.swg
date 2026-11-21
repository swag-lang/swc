using Core

func readDirectorySizes(dataPath: string)->HashTable'(String, s32)
{
    let lines = expect File.readAllLines(dataPath)

    var folder:  String
    var folders: HashTable'(String, s32)

    for i in lines.count
    {
        let line = &lines[i]
        if line[0] == '$' do
            line.remove(0, 1)

        let command = Tokenize.split(line[], ' 'u8)
        switch command[0]
        {
        case "cd":
            if command[1] == "/" do
                folder = ""
            elif command[1] == ".." do
                folder = Path.directoryName(folder)
            else do
                folder = Path.combine(folder, command[1])

        case "ls", "dir":
            break

        default:
            let size = expect StrConv.toS32(command[0])
            var currentFolder = folder
            for
            {
                folders.findOrAdd(currentFolder).value += size
                if not currentFolder.length do
                    break
                currentFolder = Path.directoryName(currentFolder)
            }
        }
    }

    return folders
}

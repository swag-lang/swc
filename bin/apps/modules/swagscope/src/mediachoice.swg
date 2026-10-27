#global internal

using Core

// A manual release match belongs to one version of a file, not merely to its reusable name.
struct MusicChoice
{
    path:          String
    size:          u64
    creationStamp: u64
    modifiedStamp: u64
    id:            String
}

func musicChoiceId(choices: const [..] MusicChoice, entry: const *ExplorerEntry)->string
{
    for &choice in choices where choice.path == entry.path and
                                 choice.size == entry.size and
                                 choice.creationStamp == entry.creationStamp and
                                 choice.modifiedStamp == entry.modifiedStamp do
        return choice.id.toString()
    return ""
}

func setMusicChoice(choices: *Array'MusicChoice, entry: const *ExplorerEntry, id: string)
{
    for index in reversed(choices.count)
    {
        if choices[index].path == entry.path do
            choices.removeAtOrdered(index)
    }

    if id.count == 0 do
        return
    if choices.count >= 1000 do
        choices.removeAtOrdered(0)
    choices.add({path: entry.path, size: entry.size, creationStamp: entry.creationStamp,
                 modifiedStamp: entry.modifiedStamp, id: id})
}

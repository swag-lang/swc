#global internal

using Core

// Polls metadata off the GUI thread and waits for two identical observations before reloading.
// Watching the path also detects editors that save by replacing the file atomically.
struct ViewerFileWatch
{
    load:          Viewer.BackgroundLoad'File.FileInfo
    current:       File.FileInfo
    candidate:     File.FileInfo
    hasCandidate:  bool
    ignorePending: bool
}

impl ViewerFileWatch
{
    func sameFile(a, b: File.FileInfo)->bool => a.size == b.size and a.lastWriteTime == b.lastWriteTime and a.creationTime == b.creationTime

    mtd poll(fileName: string)->bool
    {
        if not .load.started
        {
            .load.start(fileName, &File.info)
            return false
        }

        if not .load.isDone() do
            return false

        let matchesPath = .load.fileName == fileName and not .ignorePending
        .ignorePending = false
        var info: File.FileInfo
        let error = .load.finish(&info)
        if not matchesPath or not error.isEmpty()
        {
            .hasCandidate = false
            return false
        }

        if sameFile(info, .current)
        {
            .hasCandidate = false
            return false
        }

        if .hasCandidate and sameFile(info, .candidate) do
            return true

        .candidate    = #move info
        .hasCandidate = true
        return false
    }
}

#global public

using Core, Pixel

// Identifies a glyph of the theme's vector icon set.
//
// The set is one vector document, `theme/icons.svg`. Every glyph is an outline on a 16-unit grid:
// a stroke of 1.4 with round caps and joins, and no fill except for a deliberate dot or a media
// triangle, so a glyph shown at 16 pixels carries exactly the weight the charter asks for. The
// theme rasterizes it on demand at the requested display size and the current atlas scale, so any
// size stays sharp on any display. The declaration order is the glyph order of the document grid.
enum ThemeIcons
{
    WndMinimize     // Window-caption minimize glyph.
    WndMaximize     // Window-caption maximize glyph.
    WndClose        // Window-caption close glyph.
    Search          // Search action glyph.

    // The chevron family: one open angle per direction, and the only marker the interface uses
    // to say "there is more this way". A drop-down, a submenu, a tree branch, a property row, a
    // sort order and the arrow of a menu button are all one of these four, so a reader learns
    // the shape once. Draw them at [[Gui.ThemeMetrics.chevron_Size]].
    ChevronUp          // Points up: an ascending sort, a value that grows.
    ChevronDown        // Points down: a drop-down, an expanded branch, a descending sort.
    ChevronLeft        // Points left: a step back, a panel that closes leftward.
    ChevronRight       // Points right: a submenu, a collapsed branch, a step forward.
    Picker             // Eyedropper or picker action glyph.
    Play               // Media play action glyph.
    Pause              // Media pause action glyph.
    Stop               // Media stop action glyph.
    SendToBack         // Send-to-back ordering action.
    SendBackward       // Send-backward ordering action.
    BringForward       // Bring-forward ordering action.
    BringToFront       // Bring-to-front ordering action.
    Plus               // Add action glyph.
    More               // Additional-actions glyph.
    Undo               // Undo action glyph.
    Redo               // Redo action glyph.
    Copy               // Clipboard copy action.
    Paste              // Clipboard paste action.
    Cut                // Clipboard cut action.
    RemoveAll          // Remove-all action glyph.
    Remove             // Remove action glyph.
    Options            // Options or settings action.
    About              // About or information action.
    ZoomIn             // Zoom-in action glyph.
    ZoomOut            // Zoom-out action glyph.
    Save               // Save action glyph.
    SaveAs             // Save-as action glyph.
    Export             // Export action glyph.
    Download           // Download action glyph.
    OpenFile           // Open-file action glyph.
    Update             // Refresh or update action.
    Duplicate          // Duplicate action glyph.
    Quit               // Quit application action.
    Link               // Link action glyph.
    Sort               // Sort action glyph.
    Edit               // Edit action glyph.
    Filter             // Filter action glyph.
    Minimize           // Generic minimize action glyph.
    ParentFolder       // Up navigation toward the parent location.
    Question           // Question or confirmation status.
    Warning            // Recoverable warning status.
    Critical           // Critical error status.
    Information        // Informational status.
    HourGlass          // Waiting or in-progress status.
    Lock               // Closed padlock, for a protected or read-only object.
    Eye                // Reveals content while its action is held.
    Appearance         // Theme and language application settings.
    History            // Previously visited items or states.
    FullScreen         // Enter-full-screen action.
    ExitFullScreen     // Leave-full-screen action.
    SeekBackward       // Media seek toward an earlier position.
    SeekForward        // Media seek toward a later position.
    Volume             // Audible media volume.
    VolumeMute         // Muted media volume.
    FitView            // Fit the complete document inside its viewport.
    ActualSize         // Show content at its native size.
    Wrap               // Fold long text lines into the viewport.
    AudioTracks        // Choose one of several sound tracks.
    SearchPrevious     // Previous occurrence in a search result.
    SearchNext         // Next occurrence in a search result.
    MatchWholeWord     // Restrict a search to complete words.

    // The play modes of a folder of media: what happens once a file has been played through.
    PlayOnce          // Play the file to its end, then stop there.
    RepeatOne         // Play the same file again once it ends.
    RepeatAll         // Play the files of the folder in turn, around again past the last one.
    Shuffle           // Play the files of the folder in random order, each once before any comes again.
    OpenExternal      // Open content in another application or window.
    PlaybackSpeed     // Adjust the rate of media playback.
    ExploreFolder     // Browse the files of a folder as a gallery of previews.
    LineNumbers       // Show the number of each line beside a text.
    Settings          // Open a page of adjustable settings.
    Folder            // A folder in a file listing.
    Dot               // A filled disc that fills its box: the tone dot of a notice or a status.
    Minus             // Subtract or step-down action glyph, the counterpart of `Plus`.

    // The pages of a file listing: one page, marked with what the file holds. Ask for them through
    // [[Gui.Theme.fileGlyph]], which reads the kind from the name.
    File              // A file in a file listing, of no kind of its own.
    FileImage         // A picture.
    FileCode          // Source code, a script, or structured data.
    FileAudio         // A sound.
    FileVideo         // A film.
    FileArchive       // An archive of other files.
}

// Extensions read as each kind of file, compared without case.
private const ImageExtensions   = [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tga", ".webp", ".svg", ".ico", ".tif", ".tiff", ".psd", ".qoi"]
private const CodeExtensions    = [".swg", ".swgs", ".c", ".cpp", ".h", ".hpp", ".cs", ".js", ".ts", ".py", ".rs", ".go", ".java", ".json", ".xml", ".html", ".css", ".sh", ".bat", ".ps1", ".lua", ".toml", ".yaml", ".yml"]
private const AudioExtensions   = [".wav", ".mp3", ".flac", ".ogg", ".aac", ".m4a", ".opus", ".mid", ".midi"]
private const VideoExtensions   = [".mp4", ".mkv", ".avi", ".mov", ".webm", ".wmv", ".m4v"]
private const ArchiveExtensions = [".zip", ".7z", ".rar", ".tar", ".gz", ".bz2", ".xz"]
private const DocumentExtensions = [".pdf", ".epub", ".djvu", ".xps"]

// Reports whether `ext` is one of `list`, without case.
private func isExtensionOf(ext: string, list: const [..] string)->bool
{
    for candidate in list
    {
        if Utf8.compare(ext, candidate, .Latin1NoCase) == 0 do
            return true
    }

    return false
}

impl Theme
{
    // Creates an icon descriptor for a theme glyph displayed at `size` logical pixels.
    //
    // The frames behind a given size are rasterized once from the vector icon set, at
    // the current atlas scale, and shared by every icon of that size.
    mtd icon(idx: ThemeIcons, size = 24'f32)->Icon => .res.icons.icon(cast(s32, idx), size, .res.atlasScale)

    // Returns the line glyph of a file named `name` at `size` logical pixels: a folder, or a page
    // marked with the kind its extension says — a picture, code, a sound, a film, a paged
    // document, an archive.
    //
    // A listing draws these rather than the colored icons of the system, so a row reads by its
    // name first and the glyph only says what kind of thing it is. A kind carries its quiet hue
    // (`fileKind_*`) in the icon's color; a folder and a plain file carry none, and take the ink
    // their row gives them. A selected row may draw any of them in its own ink.
    mtd fileGlyph(name: string, isDirectory: bool, size = 16'f32)->Icon
    {
        if isDirectory do
            return .icon(.Folder, size)

        var result: #returntype
        let ext = Path.extension(name) orelse ""
        switch
        {
        case isExtensionOf(ext, ImageExtensions):
            result       = .icon(.FileImage, size)
            result.color = .colors.fileKind_Image
        case isExtensionOf(ext, CodeExtensions):
            result       = .icon(.FileCode, size)
            result.color = .colors.fileKind_Code
        case isExtensionOf(ext, AudioExtensions):
            result       = .icon(.FileAudio, size)
            result.color = .colors.fileKind_Audio
        case isExtensionOf(ext, VideoExtensions):
            result       = .icon(.FileVideo, size)
            result.color = .colors.fileKind_Video
        case isExtensionOf(ext, ArchiveExtensions):
            result       = .icon(.FileArchive, size)
            result.color = .colors.fileKind_Archive
        case isExtensionOf(ext, DocumentExtensions):
            result       = .icon(.File, size)
            result.color = .colors.fileKind_Document
        default:
            result = .icon(.File, size)
        }

        return result
    }
}

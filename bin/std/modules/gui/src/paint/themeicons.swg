#global public

// Selects theme icons24.
enum ThemeIcons24
{
    WndMinimize          // Selects wnd minimize.
    WndMaximize          // Selects wnd maximize.
    WndClose             // Selects wnd close.
    Search               // Selects search.
    RightPopupArrow      // Selects right popup arrow.
    BottomPopupArrow     // Selects bottom popup arrow.
    SortArrowDown        // Selects sort arrow down.
    SortArrowUp          // Selects sort arrow up.
    SortArrowRight       // Selects sort arrow right.
    Picker               // Selects picker.
    Play                 // Selects play.
    Pause                // Selects pause.
    Stop                 // Selects stop.
    SendToBack           // Selects send to back.
    SendBackward         // Selects send backward.
    BringForward         // Selects bring forward.
    BringToFront         // Selects bring to front.
    Plus                 // Selects plus.
    More                 // Selects more.
    Undo                 // Selects undo.
    Redo                 // Selects redo.
    Copy                 // Selects copy.
    Paste                // Selects paste.
    Cut                  // Selects cut.
    Expanded             // Selects expanded.
    Collapsed            // Selects collapsed.
    RemoveAll            // Selects remove all.
    Remove               // Selects remove.
    Options              // Selects options.
    About                // Selects about.
    ZoomIn               // Selects zoom in.
    ZoomOut              // Selects zoom out.
    Save                 // Selects save.
    SaveAs               // Selects save as.
    Export               // Selects export.
    Download             // Selects download.
    OpenFile             // Selects open file.
    Update               // Selects update.
    Duplicate            // Selects duplicate.
    Quit                 // Selects quit.
    Link                 // Selects link.
    Sort                 // Selects sort.
    Edit                 // Selects edit.
    Filter               // Selects filter.
    Minimize             // Selects minimize.
}

// Selects theme icons64.
enum ThemeIcons64
{
    Question        // Selects question.
    Warning         // Selects warning.
    Critical        // Selects critical.
    Information     // Selects information.
    HourGlass       // Selects hour glass.
}

impl Theme
{
    // Returns icon24.
    mtd getIcon24(idx: ThemeIcons24, size = 24'f32)->Icon
    {
        var result: retval
        result.imageList = .res.icons24
        result.index     = cast(s32) idx
        result.sizeX     = size
        result.sizeY     = size
        return result
    }

    // Returns icon64.
    mtd getIcon64(idx: ThemeIcons64, size = 64'f32)->Icon
    {
        var result: retval
        result.imageList = .res.icons64
        result.index     = cast(s32) idx
        result.sizeX     = size
        result.sizeY     = size
        return result
    }
}

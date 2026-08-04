#global public

// Identifies a glyph in the theme's 24-pixel action-icon atlas.
enum ThemeIcons24
{
    WndMinimize          // Window-caption minimize glyph.
    WndMaximize          // Window-caption maximize glyph.
    WndClose             // Window-caption close glyph.
    Search               // Search action glyph.
    RightPopupArrow      // Right-facing submenu indicator.
    BottomPopupArrow     // Down-facing popup indicator.
    SortArrowDown        // Descending sort indicator.
    SortArrowUp          // Ascending sort indicator.
    SortArrowRight       // Right-facing sort indicator.
    Picker               // Eyedropper or picker action glyph.
    Play                 // Media play action glyph.
    Pause                // Media pause action glyph.
    Stop                 // Media stop action glyph.
    SendToBack           // Send-to-back ordering action.
    SendBackward         // Send-backward ordering action.
    BringForward         // Bring-forward ordering action.
    BringToFront         // Bring-to-front ordering action.
    Plus                 // Add action glyph.
    More                 // Additional-actions glyph.
    Undo                 // Undo action glyph.
    Redo                 // Redo action glyph.
    Copy                 // Clipboard copy action.
    Paste                // Clipboard paste action.
    Cut                  // Clipboard cut action.
    Expanded             // Expanded tree-node indicator.
    Collapsed            // Collapsed tree-node indicator.
    RemoveAll            // Remove-all action glyph.
    Remove               // Remove action glyph.
    Options              // Options or settings action.
    About                // About or information action.
    ZoomIn               // Zoom-in action glyph.
    ZoomOut              // Zoom-out action glyph.
    Save                 // Save action glyph.
    SaveAs               // Save-as action glyph.
    Export               // Export action glyph.
    Download             // Download action glyph.
    OpenFile             // Open-file action glyph.
    Update               // Refresh or update action.
    Duplicate            // Duplicate action glyph.
    Quit                 // Quit application action.
    Link                 // Link action glyph.
    Sort                 // Sort action glyph.
    Edit                 // Edit action glyph.
    Filter               // Filter action glyph.
    Minimize             // Generic minimize action glyph.
    ParentFolder         // Up navigation toward the parent location.
}

// Identifies a glyph in the theme's 64-pixel status-icon atlas.
enum ThemeIcons64
{
    Question        // Question or confirmation status.
    Warning         // Recoverable warning status.
    Critical        // Critical error status.
    Information     // Informational status.
    HourGlass       // Waiting or in-progress status.
}

impl Theme
{
    // Creates an icon descriptor for a 24-pixel theme glyph at `size` logical pixels.
    mtd icon24(idx: ThemeIcons24, size = 24'f32)->Icon
    {
        var result: retval
        result.imageList = .res.icons24
        result.index     = cast(s32) idx
        result.sizeX     = size
        result.sizeY     = size
        return result
    }

    // Creates an icon descriptor for a 64-pixel theme glyph at `size` logical pixels.
    mtd icon64(idx: ThemeIcons64, size = 64'f32)->Icon
    {
        var result: retval
        result.imageList = .res.icons64
        result.index     = cast(s32) idx
        result.sizeX     = size
        result.sizeY     = size
        return result
    }
}

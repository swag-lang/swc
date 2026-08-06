#global public

using Core, Pixel

// Identifies a glyph of the theme's vector icon set.
//
// The set is one vector document, `theme/icons.svg`: mostly Fluent UI System Icons (MIT License),
// with the few glyphs that set does not carry drawn onto the same grid at the same weight. The
// theme rasterizes it on demand at the requested display size and the current atlas scale, so any
// size stays sharp on any display. The declaration order is the glyph order of the document grid.
enum ThemeIcons
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
    Question             // Question or confirmation status.
    Warning              // Recoverable warning status.
    Critical             // Critical error status.
    Information          // Informational status.
    HourGlass            // Waiting or in-progress status.
    Lock                 // Closed padlock, for a protected or read-only object.
}

impl Theme
{
    // Creates an icon descriptor for a theme glyph displayed at `size` logical pixels.
    //
    // The frames behind a given size are rasterized once from the vector icon set, at
    // the current atlas scale, and shared by every icon of that size.
    mtd icon(idx: ThemeIcons, size = 24'f32)->Icon
    {
        return .res.icons.icon(cast(s32) idx, size, .res.atlasScale)
    }
}

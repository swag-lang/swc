#global if #os == Swag.TargetOs.Linux

// A shared shape descriptor; X11 cursor resources are acquired lazily on the GUI connection.
#[Swag.Opaque]
struct NativeCursor
{
    public cursor: const *CursorShape?
}

private var g_CursorShapes: [CursorShape]CursorShape

#init
{
    for shape in CursorShape do
        g_CursorShapes[shape] = shape
}

public impl Cursor
{
    // Returns a shared descriptor for a standard cursor shape, without opening a display.
    func from(shape: CursorShape)->Cursor => {native: {cursor: &g_CursorShapes[shape]}}

    // Invalidates this descriptor without releasing the shared X11 cursor.
    mtd clear() { .cursor = null }

    // Applies a standard cursor to the GUI windows on the owning thread.
    //
    // X11 stores cursor selection per window. An invalid descriptor restores the arrow.
    // Shared cursor resources are released when the GUI connection closes.
    func activate(cursor: Cursor)
    {
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let shape      = cursor.cursor ? cursor.cursor[] : CursorShape.Arrow
        if context.currentCursor == shape and context.cursors[shape] != 0 do
            return
        if context.cursors[shape] == 0
        {
            if context.cursorFont == 0
            {
                let font = context.xcb_generate_id(connection)
                expect LinuxDesktop.check(context, context.xcb_open_font_checked(connection, font, 6, "cursor".buffer))
                context.cursorFont = font
            }

            var glyph: u16
            switch #complete shape
            {
            case .Arrow:                    glyph = 68
            case .ResizeHorizontal:         glyph = 108
            case .ResizeVertical:           glyph = 116
            case .ResizeNorthwestSoutheast: glyph = 134
            case .ResizeNortheastSouthwest: glyph = 136
            case .Move:                     glyph = 52
            case .Cross:                    glyph = 34
            case .Help:                     glyph = 92
            case .Hand:                     glyph = 60
            case .IBeam:                    glyph = 152
            case .No:                       glyph = 88
            case .Wait:                     glyph = 150
            }

            let id = context.xcb_generate_id(connection)
            expect LinuxDesktop.check(context,
                                      context.xcb_create_glyph_cursor_checked(connection,
                                                                              id,
                                                                              context.cursorFont,
                                                                              context.cursorFont,
                                                                              glyph,
                                                                              glyph + 1,
                                                                              0,
                                                                              0,
                                                                              0,
                                                                              65535,
                                                                              65535,
                                                                              65535))
            context.cursors[shape] = id
        }

        let id = context.cursors[shape]
        for surface in context.surfaces do
            expect LinuxDesktop.check(context, context.xcb_change_window_attributes_checked(connection, surface.windowId, 1 << 14, &id))
        context.currentCursor = shape
    }
}

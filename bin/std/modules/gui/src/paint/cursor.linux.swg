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
    // Returns a descriptor for a cursor shape, without opening a display.
    func from(shape: CursorShape)->Cursor => {native: {cursor: &g_CursorShapes[shape]}, hidden: shape == .Hidden}

    // Invalidates this descriptor without releasing the shared X11 cursor.
    mtd clear()
    {
        .cursor = null
        .hidden = false
    }

    // Applies a standard cursor to the GUI windows on the owning thread.
    //
    // X11 stores cursor selection per window. An invalid descriptor restores the arrow.
    // Shared cursor resources are released when the GUI connection closes.
    func activate(cursor: Cursor)
    {
        if LinuxDesktop.current() == null do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let shape      = cursor.isHidden() ? CursorShape.Hidden : cursor.cursor ? cursor.cursor[] : CursorShape.Arrow
        if context.currentCursor == shape and context.cursors[shape] != 0 do
            return
        if context.cursors[shape] == 0
        {
            if shape == .Hidden
            {
                let bitmap = context.xcb_generate_id(connection)
                expect LinuxDesktop.check(context, context.xcb_create_pixmap_checked(connection, 1, bitmap, context.screen.root, 1, 1))
                var bitmapOwned = true
                defer if bitmapOwned do
                    discard catch LinuxDesktop.check(context, context.xcb_free_pixmap_checked(connection, bitmap))

                let gc = context.xcb_generate_id(connection)
                expect LinuxDesktop.check(context, context.xcb_create_gc_checked(connection, gc, bitmap, 0, null))
                var gcOwned = true
                defer if gcOwned do
                    discard catch LinuxDesktop.check(context, context.xcb_free_gc_checked(connection, gc))

                // A zero ZPixmap pixel leaves every bit of the cursor mask transparent.
                var pixel: [4]u8
                pixel[0] = 0
                pixel[1] = 0
                pixel[2] = 0
                pixel[3] = 0
                expect LinuxDesktop.check(context,
                                          context.xcb_put_image_checked(connection, 2, bitmap, gc, 1, 1, 0, 0, 0, 1, cast(u32, pixel.count), pixel.buffer))

                let id = context.xcb_generate_id(connection)
                expect LinuxDesktop.check(context, context.xcb_create_cursor_checked(connection, id, bitmap, bitmap, 0, 0, 0, 0, 0, 0, 0, 0))
                context.cursors[shape] = id
                expect LinuxDesktop.check(context, context.xcb_free_gc_checked(connection, gc))
                gcOwned = false
                expect LinuxDesktop.check(context, context.xcb_free_pixmap_checked(connection, bitmap))
                bitmapOwned = false
            }
            else
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
                case .Hidden:                   glyph = 0
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
        }

        let id = context.cursors[shape]
        for surface in context.surfaces do
            expect LinuxDesktop.check(context, context.xcb_change_window_attributes_checked(connection, surface.windowId, 1 << 14, &id))
        context.currentCursor = shape
    }
}

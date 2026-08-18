#global if #os == Swag.TargetOs.Windows

using Win32

// Dependency-visible Windows storage embedded by `Cursor`.
#[Swag.Opaque, Swag.NoDoc]
public struct NativeCursor
{
    public cursor: HCURSOR     // Cursor associated with this value.
}

impl NativeCursor
{
    var defaultCursors: [CursorShape] Cursor
}

#init
{
    using NativeCursor, CursorShape
    defaultCursors[Arrow].cursor                    = LoadCursorA(null, MAKEINTRESOURCEA(IDC_ARROW))
    defaultCursors[ResizeHorizontal].cursor         = LoadCursorA(null, MAKEINTRESOURCEA(IDC_SIZEWE))
    defaultCursors[ResizeVertical].cursor           = LoadCursorA(null, MAKEINTRESOURCEA(IDC_SIZENS))
    defaultCursors[ResizeNorthwestSoutheast].cursor = LoadCursorA(null, MAKEINTRESOURCEA(IDC_SIZENWSE))
    defaultCursors[ResizeNortheastSouthwest].cursor = LoadCursorA(null, MAKEINTRESOURCEA(IDC_SIZENESW))
    defaultCursors[Move].cursor                     = LoadCursorA(null, MAKEINTRESOURCEA(IDC_SIZEALL))
    defaultCursors[Cross].cursor                    = LoadCursorA(null, MAKEINTRESOURCEA(IDC_CROSS))
    defaultCursors[Help].cursor                     = LoadCursorA(null, MAKEINTRESOURCEA(IDC_HELP))
    defaultCursors[Hand].cursor                     = LoadCursorA(null, MAKEINTRESOURCEA(IDC_HAND))
    defaultCursors[IBeam].cursor                    = LoadCursorA(null, MAKEINTRESOURCEA(IDC_IBEAM))
    defaultCursors[No].cursor                       = LoadCursorA(null, MAKEINTRESOURCEA(IDC_NO))
    defaultCursors[Wait].cursor                     = LoadCursorA(null, MAKEINTRESOURCEA(IDC_WAIT))
}

public impl Cursor
{
    // Returns the shared native cursor for a standard cursor shape.
    func from(shape: CursorShape)->Cursor
    {
        return NativeCursor.defaultCursors[shape]
    }

    // Restores an invalid cursor descriptor without destroying the shared system cursor.
    mtd clear()
    {
        .cursor = null
    }

    // Activates the cursor for the current thread.
    func activate(cursor: Cursor)
    {
        SetCursor(cursor.native.cursor)
    }
}

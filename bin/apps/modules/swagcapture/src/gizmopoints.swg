// Returns the ink of the selection marks on the canvas: the Arc of the editor's theme, which
// marks what is chosen. Without an editor, as in a headless fixture, the Arc of Encre.
func selectionInk()->Color
{
    let main = g_Main
    if main do
        return main.themeColors().arc
    return EncreArc
}

// The Arc of Encre, the theme an editor opens on.
const EncreArc: Color = 0xFF38BDF8

// Paints a round selection handle centred on `x`, `y`: a white disc ringed in `ink`, so it reads
// on any pixel of a capture. A hovered handle is filled with its ink.
func paintSelectionHandle(painter: *Painter, x, y, radius: f32, ink: Color, hot: bool)
{
    let side = radius * HandleScale
    painter.fillCircle(x, y, side, hot ? ink : Argb.White)
    painter.drawCircle(x, y, side, ink, HandleRing)
}

// A drawn handle is smaller than the area that grabs it: the reach stays generous while the mark
// stays quiet over the capture.
const HandleScale = 0.8'f32
const HandleRing  = 1.5'f32

// The handles that move the points of a line, a polygon, or a stroke.
struct GizmoPoints
{
    anchorSize: f32 = 12

    startRect:   Math.Rectangle
    anchors:     Array'Math.Point
    hotAnchor:   u32 = Swag.U32.Max
    moving:      bool
    firstMoving: bool
    movingRect:  Math.Rectangle
    movingStart: Math.Point
    sigChanged:  (func||(Math.Point, u32, bool))?

    minSizeX: f32 = 2
    minSizeY: f32 = 2
}

impl GizmoPoints
{
    // Drags the anchor under the mouse, and returns whether the gizmo handled `evt`.
    mtd mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        switch evt.kind
        {
        case .Pressed:
            if .moving do
                return true
            if evt.button != .Left or .hotAnchor == Swag.U32.Max do
                break
            .moving, .firstMoving = true
            .movingStart = pos
            view.captureMouse()
            return true

        case .Released:
            if .moving
            {
                if evt.button == .Left
                {
                    .moving, .firstMoving = false
                    .hotAnchor = Swag.U32.Max
                    view.releaseMouse()
                }

                return true
            }

        case .Move:
            if .moving
            {
                let diff = pos - .movingStart
                if .firstMoving and .sigChanged do
                    .sigChanged(diff, .hotAnchor, true)
                .firstMoving = false
                if .sigChanged do
                    .sigChanged(diff, .hotAnchor, false)
            }
            else
            {
                .hotAnchor = Swag.U32.Max
                let half = .anchorSize * 0.5
                for c, i in .anchors where Math.Rectangle{c.x - half, c.y - half, .anchorSize, .anchorSize}.contains(pos)
                {
                    .hotAnchor = cast(u32, i)
                    break
                }
            }

            if .hotAnchor != Swag.U32.Max
            {
                view.app().setFrameCursor(Cursor.from(.ResizeNorthwestSoutheast))
                return true
            }
        }

        return false
    }

    mtd paint(_: *Application?, painter: *Painter, hot: bool, col: Color)
    {
        for c in .anchors do
            paintSelectionHandle(painter, c.x, c.y, .anchorSize * 0.5, col, hot)
    }

    // Moves point `pt` of `iform` by `diff`, snapped, as one undo step that replaces the previous
    // step of the same drag unless `first`.
    func apply(iform: IForm, diff: Math.Point, pt: u32, first: bool)
    {
        let capture = unwrap iform.capture
        if not first do
            capture.undo()
        let undo     = capture.newUndo(.MovePoint)
        let editView = unwrap capture.editView
        let zoom     = editView.zoom

        undo.newPosX = cast(s32, diff.x / zoom)
        undo.newPosY = cast(s32, diff.y / zoom)
        capture.snap(&undo.newPosX, &undo.newPosY, pt > 0, pt > 0, pt)

        undo.pointIdx = pt
        undo.baseForm = iform
        capture.pushUndo(undo)
        editView.invalidate()
    }
}

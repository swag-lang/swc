struct GizmoRect
{
    paintSimpleBorder:     bool = true
    paintBigBorder:        bool = true
    roundShape:            bool = false
    anchorSize:            f32 = 12
    trackChange:           bool = false

    rect:                  Math.Rectangle
    startRect:             Math.Rectangle
    anchors:               [8] Math.Rectangle
    hotAnchor:             u32 = Swag.U32.Max
    moving:                bool
    firstMoving:           bool
    movingRect:            Math.Rectangle
    movingStart:           Math.Point
    sigChanged:            func||(*GizmoRect, bool, u32)
    sigHasChanged:         func||()

    // Rotation: the whole gizmo (box + anchors + handle) rotates with the form
    rotateEnabled:         bool = false
    rotateValue:           f32  = 0
    rotateAnchor:          Math.Rectangle
    rotateHot:             bool
    rotating:              bool
    firstRotating:         bool
    rotateStartValue:      f32
    rotateStartAngle:      f32
    sigRotate:             func||(*GizmoRect, bool, bool, f32)

    // Captured at the start of a resize so the math stays in the rotated frame
    gizmoRad:              f32
    gizmoCenter:           Math.Point

    minSizeX:              f32 = 2
    minSizeY:              f32 = 2
}

// Distance of the rotation handle above the bounding box edge
const RotateHandleDist = 26.0

impl GizmoRect
{
    mtd mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        let prop = (evt.modifiers & .Shift) and !(evt.modifiers & .Control)

        switch evt.kind
        {
        case MousePressed:
            if .moving or .rotating do
                return true
            if evt.button != .Left do
                break
            if .rotateEnabled and .rotateAnchor.contains(.toLocal(pos))
            {
                .rotating         = true
                .firstRotating    = true
                .rotateStartValue = .rotateValue
                .rotateStartAngle = .computeRotate(pos)
                view.captureMouse()
                return true
            }
            if .hotAnchor == Swag.U32.Max do
                break
            .moving, .firstMoving = true
            .gizmoRad    = .gizmoAngleRad()
            .gizmoCenter = {.rect.horzCenter(), .rect.vertCenter()}
            if .gizmoRad != 0
            {
                // Work in a frame centered on the box and aligned to its axes
                let halfW = .rect.width * 0.5
                let halfH = .rect.height * 0.5
                .startRect  = {-halfW, -halfH, .rect.width, .rect.height}
                .movingRect = .startRect
            }
            else
            {
                .startRect  = .rect
                .movingRect = .rect
            }
            .movingStart = pos
            view.captureMouse()
            return true

        case MouseReleased:
            if .rotating
            {
                if evt.button == .Left
                {
                    .rotating  = false
                    .rotateHot = false
                    view.releaseMouse()

                    // Only commit if a rotation actually happened (mouse moved)
                    if !.firstRotating
                    {
                        if .sigRotate do
                            .sigRotate(me, false, true, .rotateValue)
                        if .sigHasChanged do
                            .sigHasChanged()
                    }
                }

                return true
            }

            if .moving
            {
                if evt.button == .Left
                {
                    .moving, .firstMoving = false
                    .hotAnchor = Swag.U32.Max
                    view.releaseMouse()
                    if !.trackChange and .sigChanged do
                        .sigChanged(me, false, 0)
                    if .sigHasChanged do
                        .sigHasChanged()
                }

                return true
            }

        case MouseLeave:
            if .hotAnchor != Swag.U32.Max
            {
                .hotAnchor = Swag.U32.Max
                return true
            }

        case MouseMove:
            if .rotating
            {
                var deg = .rotateStartValue + (.computeRotate(pos) - .rotateStartAngle)
                while deg < 0 do
                    deg += 360
                while deg >= 360 do
                    deg -= 360

                // Snap to 15° steps while Shift is held
                if (evt.modifiers & .Shift) do
                    deg = Math.round(deg / 15) * 15

                .rotateValue = deg
                if .sigRotate do
                    .sigRotate(me, .firstRotating, false, deg)
                .firstRotating = false

                view.getApp().setFrameCursor(Cursor.from(.Hand))
                return true
            }

            if .moving
            {
                var hitMove = 0'u32
                if .firstMoving and .sigChanged and .trackChange do
                    .sigChanged(me, true, 0)

                .firstMoving = false

                var diff = pos - .movingStart
                .movingStart = pos

                // Express the drag in the box's own (rotated) axes
                if .gizmoRad != 0 do
                    diff = GizmoRect.rotateVec(diff, -.gizmoRad)

                switch .hotAnchor
                {
                case 0:
                    if prop
                    {
                        if Math.abs(diff.x) > Math.abs(diff.y) do
                            diff.y = diff.x
                        else do
                            diff.x = diff.y
                    }

                    .movingRect.x      = Math.min(.startRect.right() - .minSizeX, .movingRect.x + diff.x)
                    .movingRect.y      = Math.min(.startRect.bottom() - .minSizeY, .movingRect.y + diff.y)
                    .movingRect.width  = .startRect.right() - .movingRect.x
                    .movingRect.height = .startRect.bottom() - .movingRect.y
                    hitMove            = 1 | 2

                case 1:
                    .movingRect.y      = Math.min(.movingRect.y + diff.y, .startRect.bottom() - .minSizeY)
                    .movingRect.height = .startRect.bottom() - .movingRect.y
                    hitMove            = 2

                case 2:
                    if prop
                    {
                        if Math.abs(diff.x) > Math.abs(diff.y) do
                            diff.y = -diff.x
                        else do
                            diff.x = -diff.y
                    }

                    .movingRect.y      = Math.min(.startRect.bottom() - .minSizeY, .movingRect.y + diff.y)
                    .movingRect.width  = Math.max(.movingRect.width + diff.x, .minSizeX)
                    .movingRect.height = .startRect.bottom() - .movingRect.y
                    hitMove            = 2 | 4

                case 3:
                    .movingRect.x     = Math.min(.startRect.right() - .minSizeX, .movingRect.x + diff.x)
                    .movingRect.width = .startRect.right() - .movingRect.x
                    hitMove           = 1

                case 4:
                    .movingRect.width = Math.max(.movingRect.width + diff.x, .minSizeX)
                    hitMove           = 4

                case 5:
                    if prop
                    {
                        if Math.abs(diff.x) > Math.abs(diff.y) do
                            diff.y = -diff.x
                        else do
                            diff.x = -diff.y
                    }

                    .movingRect.x      = Math.min(.startRect.right() - .minSizeX, .movingRect.x + diff.x)
                    .movingRect.width  = .startRect.right() - .movingRect.x
                    .movingRect.height = Math.max(.movingRect.height + diff.y, .minSizeY)
                    hitMove            = 1 | 8

                case 6:
                    .movingRect.height = Math.max(.movingRect.height + diff.y, .minSizeY)
                    hitMove            = 8

                case 7:
                    if prop
                    {
                        if Math.abs(diff.x) > Math.abs(diff.y) do
                            diff.y = diff.x
                        else do
                            diff.x = diff.y
                    }

                    .movingRect.width  = Math.max(.movingRect.width + diff.x, .minSizeX)
                    .movingRect.height = Math.max(.movingRect.height + diff.y, .minSizeY)
                    hitMove            = 4 | 8
                }

                if .trackChange and .sigChanged do
                    .sigChanged(me, false, hitMove)
            }
            else
            {
                let lp = .toLocal(pos)
                .hotAnchor = Swag.U32.Max
                for c, i in .anchors where c.contains(lp)
                {
                    .hotAnchor = cast(u32) i
                    break
                }

                .rotateHot = .rotateEnabled and .hotAnchor == Swag.U32.Max and .rotateAnchor.contains(lp)
            }

            switch .hotAnchor
            {
            case 0, 7:
                view.getApp().setFrameCursor(Cursor.from(.SizeNWSE))
            case 1, 6:
                view.getApp().setFrameCursor(Cursor.from(.SizeNS))
            case 2, 5:
                view.getApp().setFrameCursor(Cursor.from(.SizeNESW))
            case 3, 4:
                view.getApp().setFrameCursor(Cursor.from(.SizeWE))
            }

            if .rotateHot
            {
                view.getApp().setFrameCursor(Cursor.from(.Hand))
                return true
            }

            if .hotAnchor != Swag.U32.Max do
                return true
        }

        return false
    }

    // Angle (in degrees, 0..360) of a point around the bounding box center,
    // matching the painter rotation convention (0 = up, clockwise positive).
    mtd computeRotate(pos: Math.Point)->f32
    {
        let dx  = pos.x - .rect.horzCenter()
        let dy  = pos.y - .rect.vertCenter()
        var deg = Math.toDegrees(Math.atan2(dx, -dy))
        if deg < 0 do
            deg += 360
        return deg
    }

    // Current gizmo rotation in radians (0 when the form is not rotated)
    mtd gizmoAngleRad()->f32
    {
        if !.rotateEnabled or Math.isZeroEpsilon(.rotateValue) do
            return 0
        return Math.toRadians(.rotateValue)
    }

    // Rotate a vector by the given angle (painter convention: clockwise in screen space)
    func rotateVec(v: Math.Point, ang: f32)->Math.Point
    {
        let c = Math.cos(ang)
        let s = Math.sin(ang)
        return Math.Point{c * v.x - s * v.y, s * v.x + c * v.y}
    }

    // Map a screen point into the gizmo's unrotated frame, so the axis-aligned
    // anchors/handle can be hit-tested even when the box is rotated.
    mtd toLocal(pos: Math.Point)->Math.Point
    {
        let ang = .gizmoAngleRad()
        if ang == 0 do
            return pos
        let cx = .rect.horzCenter()
        let cy = .rect.vertCenter()
        let r  = GizmoRect.rotateVec({pos.x - cx, pos.y - cy}, -ang)
        return Math.Point{cx + r.x, cy + r.y}
    }

    mtd paint(painter: *Painter, hot: bool, col: Color = Argb.White)
    {
        let anchorSize2 = .anchorSize * 0.5

        let color = Color.getBlend(Argb.Black, col, hot ? 0.8 : 1)

        // Rotate the whole gizmo (box + anchors + handle) around the box center.
        // Anchors are kept axis-aligned in storage; hit-testing un-rotates the mouse.
        // rotateTransform pivots in screen space, so map the content-space center
        // through the current transform first (otherwise the pivot drifts with zoom).
        let ang = .gizmoAngleRad()
        if ang != 0
        {
            painter.pushTransform()
            let sc = painter.getTransform().transformPoint({.rect.horzCenter(), .rect.vertCenter()})
            painter.rotateTransform(ang, sc.x, sc.y)
        }

        if .moving and !.trackChange do
            painter.drawRect(.movingRect, Pen.createDash(.Dot, color, 2))

        if !hot
        {
            if .paintSimpleBorder
            {
                painter.drawRect(.rect, color, 2)
            }
            elif .paintBigBorder
            {
                painter.drawRect(.rect, Argb.DarkGray, 4)
                var rect1 = .rect
                rect1.inflate(2)
                painter.drawRect(rect1, col, 1)
                var rect2 = .rect
                rect2.inflate(-2)
                painter.drawRect(rect2, col, 1)
            }
        }

        .anchors[0] = {.rect.x - anchorSize2, .rect.y - anchorSize2, .anchorSize, .anchorSize}
        .anchors[1] = {.rect.horzCenter() - anchorSize2, .rect.y - anchorSize2, .anchorSize, .anchorSize}
        .anchors[2] = {.rect.right() - anchorSize2, .rect.y - anchorSize2, .anchorSize, .anchorSize}
        .anchors[3] = {.rect.x - anchorSize2, .rect.vertCenter() - anchorSize2, .anchorSize, .anchorSize}
        .anchors[4] = {.rect.right() - anchorSize2, .rect.vertCenter() - anchorSize2, .anchorSize, .anchorSize}
        .anchors[5] = {.rect.x - anchorSize2, .rect.bottom() - anchorSize2, .anchorSize, .anchorSize}
        .anchors[6] = {.rect.horzCenter() - anchorSize2, .rect.bottom() - anchorSize2, .anchorSize, .anchorSize}
        .anchors[7] = {.rect.right() - anchorSize2, .rect.bottom() - anchorSize2, .anchorSize, .anchorSize}

        for c, i in .anchors
        {
            if .roundShape
            {
                painter.fillCircle(c.horzCenter(), c.vertCenter(), anchorSize2, color)
                painter.drawCircle(c.horzCenter(), c.vertCenter(), anchorSize2, Argb.Black, anchorSize2 * 0.3)
            }
            else
            {
                painter.fillRect(c, Argb.White)
                painter.drawRect(c, color, 3)
            }
        }

        // Rotation handle: sticks to the top edge (the transform rotates it with the box)
        if .rotateEnabled and !hot
        {
            let cx      = .rect.horzCenter()
            let topY    = .rect.y
            let handleY = topY - RotateHandleDist
            let knobR   = anchorSize2 + 2
            let knobCol = .rotateHot ? Argb.Yellow : col

            .rotateAnchor = {cx - knobR, handleY - knobR, knobR * 2, knobR * 2}

            // Embossed leader line, matching the big-border style (dark core + light overlay)
            painter.drawLine(cx, topY, cx, handleY, Argb.DarkGray, 4)
            painter.drawLine(cx, topY, cx, handleY, col, 2)

            // Knob: dark backing ring for depth, light fill, black outline like the anchors
            painter.fillCircle(cx, handleY, knobR + 1.5, Argb.DarkGray)
            painter.fillCircle(cx, handleY, knobR, knobCol)
            painter.drawCircle(cx, handleY, knobR, Argb.Black, knobR * 0.3)
        }

        if ang != 0 do
            painter.popTransform()
    }

    mtd apply(iform: IForm, first: bool, hitMove: u32)
    {
        let form    = cast(*BaseForm) @dataof(iform)
        let capture = form.capture
        let oldRect = iform.boundRect()
        capture.interactiveMove = true
        if !first do
            capture.undo()
        let undo = capture.newUndo(.MoveBaseForm)
        undo.baseForm = iform
        let zoom = capture.editView.zoom

        // Rotated resize: movingRect lives in the box-centered, rotated frame.
        // Convert it back to an absolute axis-aligned model box (no snapping).
        if .gizmoRad != 0
        {
            let cl  = GizmoRect.rotateVec({.movingRect.horzCenter(), .movingRect.vertCenter()}, .gizmoRad)
            let scx = .gizmoCenter.x + cl.x
            let scy = .gizmoCenter.y + cl.y

            let newW = .movingRect.width / zoom
            let newH = .movingRect.height / zoom

            let startW = .startRect.width / zoom
            let startH = .startRect.height / zoom
            let startX = (.gizmoCenter.x - .startRect.width * 0.5) / zoom
            let startY = (.gizmoCenter.y - .startRect.height * 0.5) / zoom

            undo.newPosX  = cast(s32) ((scx / zoom - newW * 0.5) - startX)
            undo.newPosY  = cast(s32) ((scy / zoom - newH * 0.5) - startY)
            undo.newSizeX = cast(s32) (newW - startW)
            undo.newSizeY = cast(s32) (newH - startH)

            capture.pushUndo(undo)
            capture.invalidateAfterMove(iform, oldRect)
            return
        }

        let dx = cast(s32) ((.movingRect.x - .startRect.x) / zoom)
        let dy = cast(s32) ((.movingRect.y - .startRect.y) / zoom)
        undo.newPosX = dx
        undo.newPosY = dy
        if hitMove & 1 do
            capture.snap(&undo.newPosX, null, false, false)
        if hitMove & 2 do
            capture.snap(null, &undo.newPosY, false, false)

        let dsx = cast(s32) ((.movingRect.width - .startRect.width) / zoom)
        let dsy = cast(s32) ((.movingRect.height - .startRect.height) / zoom)
        undo.newSizeX = dsx
        undo.newSizeY = dsy
        if hitMove & 4 do
            capture.snap(&undo.newSizeX, null, true, true)
        if hitMove & 8 do
            capture.snap(null, &undo.newSizeY, true, true)

        if hitMove & 1 do
            undo.newSizeX -= (undo.newPosX - dx)
        if hitMove & 2 do
            undo.newSizeY -= (undo.newPosY - dy)

        capture.pushUndo(undo)
        capture.invalidateAfterMove(iform, oldRect)
    }

    // Standard gizmo configuration shared by the axis-aligned box forms (image,
    // shape, step, text): same look, resize/move wired to apply(), and rotation
    // wired to applyRotate() when the form supports it.
    mtd setupForForm(iform: IForm)
    {
        .roundShape        = true
        .anchorSize        = 10
        .trackChange       = true
        .paintSimpleBorder = false
        .paintBigBorder    = true

        .sigChanged = func|form = iform|(g, first, hitMove)
        {
            g.apply(form, first, hitMove)
        }

        if iform.canRotate()
        {
            .sigRotate = func|form = iform|(g, first, last, angle)
            {
                g.applyRotate(form, first, last, angle)
            }
        }
    }

    // Apply a rotation (in degrees) to the selected form(s), mirroring the
    // Rotate slider in the property window so undo/redo stays consistent.
    mtd applyRotate(iform: IForm, first, last: bool, angle: f32)
    {
        let form    = cast(*BaseForm) @dataof(iform)
        let capture = form.capture
        if !first do
            capture.undo()

        let undo    = capture.newUndo(.SetTypedValue)
        undo.valU32 = cast #bit (u32) angle
        undo.valRef = assume Reflection.getField(BaseForm, #nameof(BaseForm.rotate))
        capture.pushUndo(undo)

        let main = capture.editView.main
        if main.quickWnd do
            main.quickWnd.updateSelection()
        if last and main.propWnd do
            main.propWnd.selectionHasChanged()
        main.editWnd.invalidate()
    }
}

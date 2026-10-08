impl Capture
{
    // Returns the point that snapping tests once moved by `nx, ny`: the edited polygon
    // point or line end when one is being dragged, otherwise the corner of `bound`
    // that `right` and `bottom` name.
    mtd getSnapPoint(bound: Math.Rectangle, right, bottom: bool, nx, ny: s32, idxPt: u32, editForm: IForm? = null)->Math.Point
    {
        var result: retval

        let form = editForm orelse .forms[.selection[0]]
        let type = Swag.kindOf(form)

        if .selection.count == 1 and type == FormPolygon
        {
            let poly = assume cast(*FormPolygon, form)
            result.x = poly.points[idxPt].x + nx
            result.y = poly.points[idxPt].y + ny
        }
        elif (.selection.count == 1 or editForm) and (type == FormLine or type == FormArrow)
        {
            let line = assume cast(*FormLine, form)
            if not right or not bottom
            {
                result.x = line.xa
                result.y = line.ya
            }
            else
            {
                result.x = line.xb
                result.y = line.yb
            }

            result.x += nx
            result.y += ny
        }
        else
        {
            result.x = right ? bound.right() : bound.x
            result.y = bottom ? bound.bottom() : bound.y
            result.x += nx
            result.y += ny
        }

        return result
    }

    // Returns the box around the selected forms, or around `editForm` when it is given.
    mtd getSelectionBoundRect(editForm: IForm? = null)->Math.Rectangle
    {
        if editForm do
            return editForm.boundRect()

        var bound = Math.Rectangle{Swag.F32.Max, Swag.F32.Max, 0, 0}
        foreachSelected'BaseForm(me, .selection)
        {
            let r = itf.boundRect()
            bound.x = Math.min(bound.x, r.x)
            bound.y = Math.min(bound.y, r.y)
            bound.setRight(Math.max(bound.right(), r.right()))
            bound.setBottom(Math.max(bound.bottom(), r.bottom()))
        }

        return bound
    }

    // The coordinates a moved point can snap to: the canvas edges and middle, and the edges or
    // points of every form, except the parts of the forms being moved.
    mtd snapLines(idxPt: u32, editForm: IForm?)->{xs: Array's32, ys: Array's32}
    {
        var result: retval

        result.xs.add(0)
        result.xs.add(.width)
        result.xs.add(.width / 2)
        result.ys.add(0)
        result.ys.add(.height)
        result.ys.add(.height / 2)

        for f, i in .forms
        {
            let autoSel = .selection.contains(i) or f.buffer == editForm.buffer
            let form    = assume cast(*BaseForm, f)

            switch f
            {
            case FormLine as form2:
                if not autoSel or (idxPt != 0 and Math.abs(form2.ya - form2.yb) > 25) do
                    result.xs.add(cast(s32, form2.xa))
                if not autoSel or (idxPt != 0 and Math.abs(form2.xa - form2.xb) > 25) do
                    result.ys.add(cast(s32, form2.ya))

                if not autoSel or idxPt != 1
                {
                    result.xs.add(cast(s32, form2.xb))
                    result.ys.add(cast(s32, form2.yb))
                }

            case FormPolygon as form2:
                for pt, idx in form2.points
                {
                    if not autoSel or idx != idxPt
                    {
                        result.xs.add(cast(s32, pt.x))
                        result.ys.add(cast(s32, pt.y))
                    }
                }

            case FormDraw:
                if autoSel do
                    continue
                let boundR = f.boundRect()
                result.xs.add(cast(s32, boundR.x))
                result.xs.add(cast(s32, boundR.right()))
                result.ys.add(cast(s32, boundR.y))
                result.ys.add(cast(s32, boundR.bottom()))

            default:
                if autoSel do
                    continue
                result.xs.add(cast(s32, form.x))
                result.xs.add(cast(s32, form.x + form.w))
                result.ys.add(cast(s32, form.y))
                result.ys.add(cast(s32, form.y + form.h))
            }
        }

        return result
    }

    // The coordinate of `candidates` nearest to `value`, and how far it is.
    func nearestSnap(value: f32, candidates: const [..] s32)->{distance: f32, coord: f32}
    {
        var result: retval
        result.distance = Swag.F32.Max
        for candidate in candidates
        {
            let distance = Math.abs(value - candidate)
            if distance < result.distance
            {
                result.distance = distance
                result.coord    = candidate
            }
        }

        return result
    }

    // Adjusts the move in `x` and `y` so the dragged point lands on the nearest edge or
    // center of another form within reach, and records the guide lines to show. Snapping
    // applies when it is on or while Control is held; a null axis is left alone.
    mtd snap(x, y: *s32?, right, bottom: bool, idxPt: u32 = 0, editForm: IForm? = null)
    {
        const SnapToler = 10

        if x do
            .snapX = -1
        if y do
            .snapY = -1

        let editView    = .editView!
        let keyboard    = &editView.app().keyboard
        let ctrlPressed = keyboard.isKeyPressed(.Control)
        if not editView.main.snap and not ctrlPressed do
            return

        var nx = x ? x[] : 0
        var ny = y ? y[] : 0

        let bound = .getSelectionBoundRect(editForm)

        let pMoved = .getSnapPoint(bound, right, bottom, nx, ny, idxPt, editForm)
        let pOrg   = .getSnapPoint(bound, right, bottom, 0, 0, idxPt, editForm)
        let lines  = .snapLines(idxPt, editForm)
        if x
        {
            let near = nearestSnap(pMoved.x, lines.xs.toSlice())
            if near.distance < SnapToler
            {
                .snapX = near.coord
                nx     = cast(s32, near.coord - pOrg.x)
            }
        }

        if y
        {
            let near = nearestSnap(pMoved.y, lines.ys.toSlice())
            if near.distance < SnapToler
            {
                .snapY = near.coord
                ny     = cast(s32, near.coord - pOrg.y)
            }
        }

        if x do
            x[] = nx
        if y do
            y[] = ny
    }
}

impl Capture
{
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

        var arrX: Array's32
        var arrY: Array's32

        arrX.add(0)
        arrX.add(.width)
        arrX.add(.width / 2)
        arrY.add(0)
        arrY.add(.height)
        arrY.add(.height / 2)

        for f, i in .forms
        {
            let autoSel = .selection.contains(i) or f.buffer == editForm.buffer
            let form    = assume cast(*BaseForm, f)

            switch f
            {
            case FormLine as form2:
                if not autoSel or (idxPt != 0 and Math.abs(form2.ya - form2.yb) > 25) do
                    arrX.add(cast(s32, form2.xa))
                if not autoSel or (idxPt != 0 and Math.abs(form2.xa - form2.xb) > 25) do
                    arrY.add(cast(s32, form2.ya))

                if not autoSel or idxPt != 1
                {
                    arrX.add(cast(s32, form2.xb))
                    arrY.add(cast(s32, form2.yb))
                }

            case FormPolygon as form2:
                for pt, idx in form2.points
                {
                    if not autoSel or idx != idxPt
                    {
                        arrX.add(cast(s32, pt.x))
                        arrY.add(cast(s32, pt.y))
                    }
                }

            case FormDraw:
                if autoSel do
                    continue
                let boundR = f.boundRect()
                arrX.add(cast(s32, boundR.x))
                arrX.add(cast(s32, boundR.right()))
                arrY.add(cast(s32, boundR.y))
                arrY.add(cast(s32, boundR.bottom()))

            default:
                if autoSel do
                    continue
                arrX.add(cast(s32, form.x))
                arrX.add(cast(s32, form.x + form.w))
                arrY.add(cast(s32, form.y))
                arrY.add(cast(s32, form.y + form.h))
            }
        }

        var bestX      = Swag.F32.Max
        var bestY      = Swag.F32.Max
        var bestCoordX = 0.0
        var bestCoordY = 0.0

        let pMoved = .getSnapPoint(bound, right, bottom, nx, ny, idxPt, editForm)

        if x
        {
            for ax in arrX
            {
                let nbX = Math.abs(pMoved.x - ax)
                if nbX < bestX
                {
                    bestX      = nbX
                    bestCoordX = ax
                }
            }
        }

        if y
        {
            for ay in arrY
            {
                let nbY = Math.abs(pMoved.y - ay)
                if nbY < bestY
                {
                    bestY      = nbY
                    bestCoordY = ay
                }
            }
        }

        let pOrg = .getSnapPoint(bound, right, bottom, 0, 0, idxPt, editForm)

        if x and bestX < SnapToler
        {
            .snapX = bestCoordX
            nx     = cast(s32, bestCoordX - pOrg.x)
        }

        if y and bestY < SnapToler
        {
            .snapY = bestCoordY
            ny     = cast(s32, bestCoordY - pOrg.y)
        }

        if x do
            x[] = nx
        if y do
            y[] = ny
    }
}

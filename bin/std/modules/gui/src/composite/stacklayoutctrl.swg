#global public

using Core

enum StackLayoutKind
{
    Top            // From top to bottom
    Bottom         // From bottom to top
    Left           // From left to right
    Right          // From right to left
    HorzCenter     // Center horizontally
    HorzCenterVertCenter
    VertCenter     // Center vertically
    HorzFit        // From left to right; fit the available room
    VertFit        // From top to bottom; fit the available room
}

struct StackLayoutCtrl
{
    using wnd: Wnd

    layoutKind:   StackLayoutKind = Top
    spacing:      f32 = 5
    fitToContent: bool
}

impl IWnd for StackLayoutCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()
        .wnd.IWnd.onResizeEvent(evt)
    }
}

private impl StackLayoutCtrl
{
    mtd isHorizontal()->bool
    {
        switch .layoutKind
        {
        case Left, Right, HorzCenter, HorzCenterVertCenter, HorzFit: return true
        }

        return false
    }

    mtd isReverse()->bool
    {
        return .layoutKind == .Bottom or .layoutKind == .Right
    }

    mtd isCenteringMain()->bool
    {
        return .layoutKind == .HorzCenter or .layoutKind == .HorzCenterVertCenter or .layoutKind == .VertCenter
    }

    mtd isFitMain()->bool
    {
        return .layoutKind == .HorzFit or .layoutKind == .VertFit
    }

    mtd mainFromPoint(pt: Math.Point)->f32
    {
        return .isHorizontal() ? pt.x : pt.y
    }

    mtd crossFromPoint(pt: Math.Point)->f32
    {
        return .isHorizontal() ? pt.y : pt.x
    }

    mtd mainFromRect(rect: Math.Rectangle)->f32
    {
        return .isHorizontal() ? rect.width : rect.height
    }

    mtd crossFromRect(rect: Math.Rectangle)->f32
    {
        return .isHorizontal() ? rect.height : rect.width
    }

    mtd mainMargin(margin: Math.Vector4)->f32
    {
        return .isHorizontal() ? margin.x + margin.z : margin.y + margin.w
    }

    mtd crossMargin(margin: Math.Vector4)->f32
    {
        return .isHorizontal() ? margin.y + margin.w : margin.x + margin.z
    }

    mtd startMargin(margin: Math.Vector4)->f32
    {
        return .isHorizontal() ? margin.x : margin.y
    }

    mtd endMargin(margin: Math.Vector4)->f32
    {
        return .isHorizontal() ? margin.z : margin.w
    }

    mtd crossStartMargin(margin: Math.Vector4)->f32
    {
        return .isHorizontal() ? margin.y : margin.x
    }

    mtd crossEndMargin(margin: Math.Vector4)->f32
    {
        return .isHorizontal() ? margin.w : margin.z
    }

    mtd mainPolicy(wnd: *Wnd)->SizePolicy
    {
        return .isHorizontal() ? wnd.layoutSpec.policyX : wnd.layoutSpec.policyY
    }

    mtd crossPolicy(wnd: *Wnd)->SizePolicy
    {
        return .isHorizontal() ? wnd.layoutSpec.policyY : wnd.layoutSpec.policyX
    }

    mtd mainWeight(wnd: *Wnd)->f32
    {
        return Math.max(.isHorizontal() ? wnd.layoutSpec.weightX : wnd.layoutSpec.weightY, 0)
    }

    mtd canShrinkMain(wnd: *Wnd)->bool
    {
        let pol = .mainPolicy(wnd)
        return pol == SizePolicy.Fill or pol == SizePolicy.Expand
    }

    mtd setRectMain(rect: *Math.Rectangle, pos, size: f32)
    {
        if .isHorizontal()
        {
            rect.x     = pos
            rect.width = size
        }
        else
        {
            rect.y      = pos
            rect.height = size
        }
    }

    mtd setRectCross(rect: *Math.Rectangle, pos, size: f32)
    {
        if .isHorizontal()
        {
            rect.y      = pos
            rect.height = size
        }
        else
        {
            rect.x     = pos
            rect.width = size
        }
    }

    mtd preferredMain(hint: SizeHint)->f32  => .mainFromPoint(hint.preferred)
    mtd minimumMain(hint: SizeHint)->f32    => .mainFromPoint(hint.min)
    mtd maximumMain(hint: SizeHint)->f32    => .mainFromPoint(hint.max)
    mtd preferredCross(hint: SizeHint)->f32 => .crossFromPoint(hint.preferred)
    mtd minimumCross(hint: SizeHint)->f32   => .crossFromPoint(hint.min)
    mtd maximumCross(hint: SizeHint)->f32   => .crossFromPoint(hint.max)

    mtd arrangeLinear()
    {
        let client = .getClientRectPadding()
        let availableMain = .mainFromRect(client)
        let availableCross = .crossFromRect(client)

        var visible:  Array'(*Wnd)
        var hints:    Array'SizeHint
        var oldSizes: Array'Math.Point
        for c in .childs
        {
            if !c.isVisibleState() do
                continue
            visible.add(c)
            hints.add(c.measure({client.width, client.height}))
            oldSizes.add({c.position.width, c.position.height})
        }

        if visible.isEmpty() do
            return

        let count = cast(f32) visible.count
        let spacingTotal = cast(f32) (visible.count - 1) * .spacing

        var totalPreferred = spacingTotal
        var totalMinimum = spacingTotal
        var totalMargins = 0'f32
        var totalWeight = 0'f32
        var shrinkPool = 0'f32
        for c, idx in visible
        {
            let margin = c.getLayoutMargin()
            let marginMain = .mainMargin(margin)
            totalMargins   += marginMain
            totalPreferred += .preferredMain(hints[idx]) + marginMain
            totalMinimum   += .minimumMain(hints[idx]) + marginMain
            if .canShrinkMain(c) do
                shrinkPool += Math.max(.preferredMain(hints[idx]) - .minimumMain(hints[idx]), 0)
            let pol = .mainPolicy(c)
            if pol == SizePolicy.Expand or pol == SizePolicy.Fill or .isFitMain()
            {
                var itemWeight = 1'f32
                if !.isFitMain() do
                    itemWeight = .mainWeight(c)
                totalWeight    += itemWeight
            }
        }

        var extra = 0'f32
        var shortage = 0'f32
        if .isFitMain()
        {
            totalWeight    = count
            extra          = Math.max(availableMain - totalMinimum, 0)
            totalPreferred = totalMinimum
        }
        elif .fitToContent do
            shortage = 0
        elif availableMain >= totalPreferred do
            extra = availableMain - totalPreferred
        else do
            shortage = totalPreferred - availableMain

        var cursor: f32
        if .isReverse() do
            cursor = .isHorizontal() ? client.right() : client.bottom()
        elif .isCenteringMain() do
            cursor = (.isHorizontal() ? client.x : client.y) + Math.max(availableMain - totalPreferred, 0) * 0.5
        else do
            cursor = .isHorizontal() ? client.x : client.y

        var contentEnd = 0'f32
        for idxLoop in visible.count
        {
            let idx = idxLoop
            let c = visible[idx]
            let hint = hints[idx]
            let margin = c.getLayoutMargin()

            var mainSize = .preferredMain(hint)
            if .isFitMain()
            {
                let availableForItems = Math.max(availableMain - spacingTotal - totalMargins, 0)
                mainSize = availableForItems / count
            }
            elif extra > 0 and totalWeight > 0
            {
                let pol = .mainPolicy(c)
                if pol == SizePolicy.Expand or pol == SizePolicy.Fill
                {
                    let w = .mainWeight(c)
                    mainSize += extra * w / totalWeight
                }
            }
            elif shortage > 0 and shrinkPool > 0
            {
                if .canShrinkMain(c)
                {
                    let shrink = .preferredMain(hint) - .minimumMain(hint)
                    mainSize -= shortage * shrink / shrinkPool
                }
            }

            mainSize = Math.clamp(mainSize, .minimumMain(hint), .maximumMain(hint))

            var crossSize: f32
            let crossAvailable = Math.max(availableCross - .crossMargin(margin), 0)
            let polCross = .crossPolicy(c)
            let align = .isHorizontal() ? c.layoutSpec.alignY : c.layoutSpec.alignX
            if !.isCenteringMain() and (align == LayoutAlign.Stretch or polCross == SizePolicy.Fill or polCross == SizePolicy.Expand) do
                crossSize = crossAvailable
            else do
                crossSize = .preferredCross(hint)
            crossSize     = Math.clamp(crossSize, .minimumCross(hint), .maximumCross(hint))

            var mainPos: f32
            if .isReverse()
            {
                cursor  -= .endMargin(margin) + mainSize
                mainPos = cursor
                cursor  -= .startMargin(margin) + .spacing
            }
            else
            {
                mainPos = cursor + .startMargin(margin)
                cursor  += .startMargin(margin) + mainSize + .endMargin(margin) + .spacing
            }

            let crossBase = .isHorizontal() ? client.y : client.x
            var crossPos = crossBase + .crossStartMargin(margin)
            if .layoutKind == .HorzCenterVertCenter or .layoutKind == .VertCenter or align == LayoutAlign.Center do
                crossPos = crossBase + (availableCross - crossSize) * 0.5
            elif align == LayoutAlign.End do
                crossPos = crossBase + availableCross - .crossEndMargin(margin) - crossSize

            var rect: Math.Rectangle
            .setRectMain(&rect, Math.round(mainPos), Math.round(mainSize))
            .setRectCross(&rect, Math.round(crossPos), Math.round(crossSize))
            c.arrange(rect)
            c.applyLayout(oldSizes[idx])
            let actualMainSize = .mainFromRect(c.position)
            let mainDelta = actualMainSize - mainSize
            if mainDelta != 0
            {
                if .isReverse()
                {
                    var pos = c.position
                    if .isHorizontal() do
                        pos.x -= mainDelta
                    else do
                        pos.y -= mainDelta
                    c.setPosition(pos, false)
                    cursor -= mainDelta
                }
                else do
                    cursor += mainDelta
            }

            if .isHorizontal() do
                contentEnd = Math.max(contentEnd, c.position.right() + margin.z + .padding.z)
            else do
                contentEnd = Math.max(contentEnd, c.position.bottom() + margin.w + .padding.w)
        }

        if .fitToContent
        {
            if .isHorizontal()
            {
                .position.width  = contentEnd
                .preferredSize.x = contentEnd
            }
            else
            {
                .position.height = contentEnd
                .preferredSize.y = contentEnd
            }
        }
    }
}

impl StackLayoutCtrl
{
    // Create a layout control
    func create(parent: *Wnd, kind: StackLayoutKind = .Top, position: Math.Rectangle = {})->*StackLayoutCtrl
    {
        let res = Wnd.create'StackLayoutCtrl(parent, position)
        res.layoutKind = kind
        return res
    }

    // Recompute layout of all childs
    mtd computeLayout()
    {
        .arrangeLinear()
    }

    mtd applyLayout()
    {
        .computeLayout()
    }

    mtd applyLayout(oldSize: Math.Point)
    {
        discard oldSize
        .computeLayout()
    }
}

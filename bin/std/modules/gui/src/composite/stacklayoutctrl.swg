#global public

using Core

// Selects the direction and distribution policy of a stack layout.
enum StackLayoutMode
{
    Top                  // Stacks vertically from top to bottom.
    Bottom               // Stacks vertically from bottom to top.
    Left                 // Stacks horizontally from left to right.
    Right                // Stacks horizontally from right to left.
    HorizontalCenter     // Centers a left-to-right stack horizontally.
    Center               // Centers a left-to-right stack on both axes.
    VerticalCenter       // Centers a top-to-bottom stack vertically.
    HorizontalFit        // Divides horizontal space evenly between children.
    VerticalFit          // Divides vertical space evenly between children.
    HorizontalEnd        // Aligns a left-to-right stack to the trailing edge.
}

// Arranges visible children as a one-dimensional stack.
struct StackLayoutCtrl
{
    public
    {
        using wnd: Wnd     // Embedded wnd state.

        mode:         StackLayoutMode = Top     // Direction and distribution policy.
        spacing:      f32             = 5       // Gap between adjacent children.
        fitToContent: bool                      // Whether the control resizes along the stacking axis to its content.
    }
}

impl IWnd for StackLayoutCtrl
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .computeLayout()
        .wnd.IWnd.onResizeEvent(evt)
    }

    // Reports the room the stacked children need, spacing, margins and padding included.
    //
    // This is what lets a docked band be as tall as what it holds instead of carrying a
    // height written by hand: give the stack no size on its stacking axis and the layout
    // pass asks it here. A distributing mode fills whatever it is given, so it answers
    // for its content all the same and the container decides.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        let padding    = .padding
        let horizontal = .isHorizontal()

        var childAvailable: Math.Point
        if horizontal do
            childAvailable.y = Math.max(available.y - padding.y - padding.w, 0)
        else do
            childAvailable.x = Math.max(available.x - padding.x - padding.z, 0)

        var main, cross: f32
        var count:       u64
        for c in .children
        {
            if !c.isLocallyVisible() do
                continue

            let margin = c.layoutMargin()
            let hint   = c.measure(childAvailable)
            main  += .preferredMain(hint) + .mainMargin(margin)
            cross = Math.max(cross, .preferredCross(hint) + .crossMargin(margin))
            count += 1
        }

        if !count do
            return {}

        main += cast(f32) (count - 1) * .spacing

        var result: retval
        if horizontal
        {
            result.x = main + padding.x + padding.z
            result.y = cross + padding.y + padding.w
        }
        else
        {
            result.x = cross + padding.x + padding.z
            result.y = main + padding.y + padding.w
        }

        return result
    }
}

private impl StackLayoutCtrl
{
    mtd isHorizontal()->bool
    {
        switch .mode
        {
        case .Left, .Right, .HorizontalEnd, .HorizontalCenter, .Center, .HorizontalFit: return true
        }

        return false
    }

    mtd isReverse()->bool
    {
        return .mode == .Bottom or .mode == .Right
    }

    mtd isCenteringMain()->bool
    {
        return .mode == .HorizontalCenter or .mode == .Center or .mode == .VerticalCenter
    }

    mtd isEndingMain()->bool
    {
        return .mode == .HorizontalEnd
    }

    mtd isFitMain()->bool
    {
        return .mode == .HorizontalFit or .mode == .VerticalFit
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
        return pol == SizePolicy.Expand
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
        let client         = .paddedClientRect()
        let availableMain  = .mainFromRect(client)
        let availableCross = .crossFromRect(client)

        var visible:  Array'(*Wnd)
        var hints:    Array'SizeHint
        var oldSizes: Array'Math.Point
        for c in .children
        {
            if !c.isLocallyVisible() do
                continue
            visible.add(c)
            hints.add(c.measure({client.width, client.height}))
            oldSizes.add({c.position.width, c.position.height})
        }

        if visible.isEmpty() do
            return

        let count        = cast(f32) visible.count
        let spacingTotal = cast(f32) (visible.count - 1) * .spacing

        var totalPreferred = spacingTotal
        var totalMinimum   = spacingTotal
        var totalMargins   = 0'f32
        var totalWeight    = 0'f32
        var shrinkPool     = 0'f32
        for c, idx in visible
        {
            let margin     = c.layoutMargin()
            let marginMain = .mainMargin(margin)
            totalMargins   += marginMain
            totalPreferred += .preferredMain(hints[idx]) + marginMain
            totalMinimum   += .minimumMain(hints[idx]) + marginMain
            if .canShrinkMain(c) do
                shrinkPool += Math.max(.preferredMain(hints[idx]) - .minimumMain(hints[idx]), 0)
            let pol = .mainPolicy(c)
            if pol == SizePolicy.Expand or .isFitMain()
            {
                var itemWeight = 1'f32
                if !.isFitMain() do
                    itemWeight = .mainWeight(c)
                totalWeight += itemWeight
            }
        }

        var extra    = 0'f32
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
        elif .isEndingMain() do
            cursor = client.x + Math.max(availableMain - totalPreferred, 0)
        elif .isCenteringMain() do
            cursor = (.isHorizontal() ? client.x : client.y) + Math.max(availableMain - totalPreferred, 0) * 0.5
        else do
            cursor = .isHorizontal() ? client.x : client.y

        var contentEnd = 0'f32
        for idxLoop in visible.count
        {
            let idx    = idxLoop
            let c      = visible[idx]
            let hint   = hints[idx]
            let margin = c.layoutMargin()

            var mainSize = .preferredMain(hint)
            if .isFitMain()
            {
                let availableForItems = Math.max(availableMain - spacingTotal - totalMargins, 0)
                mainSize = availableForItems / count
            }
            elif extra > 0 and totalWeight > 0
            {
                let pol = .mainPolicy(c)
                if pol == SizePolicy.Expand
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
            let polCross       = .crossPolicy(c)
            let align          = .isHorizontal() ? c.layoutSpec.alignY : c.layoutSpec.alignX
            if !.isCenteringMain() and (align == LayoutAlign.Stretch or polCross == SizePolicy.Expand) do
                crossSize = crossAvailable
            else do
                crossSize = .preferredCross(hint)
            crossSize = Math.clamp(crossSize, .minimumCross(hint), .maximumCross(hint))

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
            var crossPos  = crossBase + .crossStartMargin(margin)
            if .mode == .Center or .mode == .VerticalCenter or align == LayoutAlign.Center do
                crossPos = crossBase + (availableCross - crossSize) * 0.5
            elif align == LayoutAlign.End do
                crossPos = crossBase + availableCross - .crossEndMargin(margin) - crossSize

            var rect: Math.Rectangle
            .setRectMain(&rect, Math.round(mainPos), Math.round(mainSize))
            .setRectCross(&rect, Math.round(crossPos), Math.round(crossSize))
            c.arrange(rect)
            c.applyLayout(oldSizes[idx])
            let actualMainSize = .mainFromRect(c.position)
            let mainDelta      = actualMainSize - mainSize
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
    // Creates an empty stack using `mode`.
    func create(parent: *Wnd, mode: StackLayoutMode = .Top, position: Math.Rectangle = {})->*StackLayoutCtrl
    {
        let res = Wnd.create'StackLayoutCtrl(parent, position)
        res.mode = mode
        return res
    }

    // Recomputes the arrangement of all visible children.
    mtd computeLayout()
    {
        .arrangeLinear()
    }

    // Recomputes the arrangement after a parent layout pass.
    mtd applyLayout()
    {
        .computeLayout()
    }

    // Recomputes the arrangement after a parent resize.
    mtd applyLayout(oldSize: Math.Point)
    {
        discard oldSize
        .computeLayout()
    }
}

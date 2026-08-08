#global public
#global namespace Svg

using Core, Core.Math

// One filled and/or stroked shape of a parsed [[Svg.Drawing]].
//
// The contours are stored in the drawing's user units, already transformed by the
// group transforms they were parsed under.
#[Swag.Opaque]
struct Shape
{
    internal
    {
        pathList: LinePathList     // Contours, in drawing user units.

        fillColor: Color     // Straight-alpha fill color.
        hasFill:   bool      // Whether the shape is filled.
        evenOdd:   bool      // Whether the fill uses the even-odd rule.

        hidden: bool     // Whether the shape is a reusable definition, not painted directly.

        strokeColor: Color                    // Straight-alpha stroke color.
        strokeWidth: f32          = 1         // Stroke width, in user units.
        hasStroke:   bool                     // Whether the shape is stroked.
        capStyle:    LineCapStyle = None      // Cap applied to open subpath ends.
        joinStyle:   JoinStyle    = Miter     // Join between stroke segments.
    }
}

// A parsed vector document, ready to paint at any scale.
//
// [[Pixel.Svg.Drawing.parse]] reads the SVG subset the standard themes are authored in:
// `svg`, `g`, `path`, `rect`, `circle`, `ellipse`, `line`, `polygon` and `polyline`
// elements; `translate`/`scale` transforms; solid fills and strokes with opacity.
// Gradients, filters, text, and rotations are out of contract. Because nothing is
// rasterized at parse time, the same drawing renders pixel perfect at every size.
struct Drawing
{
    width:  f32     // View-box width, in user units.
    height: f32     // View-box height, in user units.

    internal
    shapes: Array'Shape     // Shapes in paint order.
}

// Attribute state inherited through `svg` and `g` elements.
private struct GroupState
{
    tx, ty: f32         // Accumulated translation, in drawing units.
    sx, sy: f32 = 1     // Accumulated scale.

    fillColor: Color = Color.fromArgb(Argb.Black)     // Inherited fill color.
    hasFill:   bool  = true                           // Whether fill is enabled.
    evenOdd:   bool                                   // Inherited fill rule.

    strokeColor: Color                    // Inherited stroke color.
    strokeWidth: f32          = 1         // Inherited stroke width, in user units.
    hasStroke:   bool                     // Whether stroke is enabled.
    capStyle:    LineCapStyle = None      // Inherited stroke cap.
    joinStyle:   JoinStyle    = Miter     // Inherited stroke join.

    opacity: f32 = 1     // Accumulated group opacity.
    inDefs:  bool        // Whether the element sits inside a `defs` scope.
}

private struct Parser
{
    text:    string     // Whole document.
    pos:     u64        // Read position.
    drawing: *Drawing = undefined

    // Shapes defined inside `defs`, by id, instantiated by `use` elements. The
    // ranges index the drawing's shape array: defs shapes are parsed in place and
    // withheld from painting.
    defs:   HashTable'(String, { first: u64, count: u64 })
    inDefs: bool     // Whether parsing currently sits inside a `defs` element.
}

// Numeric scanning /////////////////////////////////////////////////////////////

private func isNumberStart(c: u8)->bool
{
    return (c >= '0' and c <= '9') or c == '-' or c == '+' or c == '.'
}

// Scans one floating-point number of a path or attribute value.
private func scanNumber(s: string, pos: *u64)->f32
{
    let len = @countof(s)
    var i   = dref pos
    while i < len and (s[i] == ' ' or s[i] == ',' or s[i] == '\t' or s[i] == '\n' or s[i] == '\r') do
        i += 1

    let start = i
    if i < len and (s[i] == '-' or s[i] == '+') do
        i += 1
    while i < len and s[i] >= '0' and s[i] <= '9' do
        i += 1
    if i < len and s[i] == '.'
    {
        i += 1
        while i < len and s[i] >= '0' and s[i] <= '9' do
            i += 1
    }

    if i < len and (s[i] == 'e' or s[i] == 'E')
    {
        i += 1
        if i < len and (s[i] == '-' or s[i] == '+') do
            i += 1
        while i < len and s[i] >= '0' and s[i] <= '9' do
            i += 1
    }

    dref pos = i
    if i == start do
        return 0
    return catch StrConv.toF32(cast(string) @mkslice(@dataof(s) + start, i - start))
}

// Colors ///////////////////////////////////////////////////////////////////////

private func hexNibble(c: u8)->u8
{
    if c >= '0' and c <= '9' do
        return c - '0'
    if c >= 'a' and c <= 'f' do
        return c - 'a' + 10
    if c >= 'A' and c <= 'F' do
        return c - 'A' + 10
    return 0
}

// Parses a solid paint value. Returns the color and whether painting is enabled.
private func parseColor(value: string)->{ color: Color, enabled: bool }
{
    var result: retval
    result.color   = Color.fromArgb(Argb.Black)
    result.enabled = true

    if value == "none" or value == "transparent"
    {
        result.enabled = false
        return result
    }

    if value == "white"
    {
        result.color = Color.fromArgb(Argb.White)
        return result
    }

    if value == "black" do
        return result

    let len = @countof(value)
    if len and value[0] == '#'
    {
        if len == 4 or len == 5
        {
            let r = hexNibble(value[1]) * 17
            let g = hexNibble(value[2]) * 17
            let b = hexNibble(value[3]) * 17
            let a = len == 5 ? hexNibble(value[4]) * 17 : 255'u8
            result.color = Color.fromArgb(a, r, g, b)
            return result
        }

        if len == 7 or len == 9
        {
            let r = hexNibble(value[1]) * 16 + hexNibble(value[2])
            let g = hexNibble(value[3]) * 16 + hexNibble(value[4])
            let b = hexNibble(value[5]) * 16 + hexNibble(value[6])
            let a = len == 9 ? hexNibble(value[7]) * 16 + hexNibble(value[8]) : 255'u8
            result.color = Color.fromArgb(a, r, g, b)
            return result
        }
    }

    if len > 4 and cast(string) @mkslice(@dataof(value), 4) == "rgb("
    {
        var pos = 4'u64
        let r   = scanNumber(value, &pos)
        let g   = scanNumber(value, &pos)
        let b   = scanNumber(value, &pos)
        result.color = Color.fromArgb(255, cast(u8) Math.clamp(r, 0, 255), cast(u8) Math.clamp(g, 0, 255), cast(u8) Math.clamp(b, 0, 255))
        return result
    }

    return result
}

// Group attributes /////////////////////////////////////////////////////////////

private func applyStyleProperty(state: *GroupState, name, value: string)
{
    switch name
    {
    case "fill":
        let {color, enabled} = parseColor(value)
        state.hasFill = enabled
        if enabled do
            state.fillColor = color

    case "stroke":
        let {color, enabled} = parseColor(value)
        state.hasStroke = enabled
        if enabled do
            state.strokeColor = color

    case "fill-opacity":
        var pos = 0'u64
        let o   = Math.saturate(scanNumber(value, &pos))
        state.fillColor.a = cast(u8) Math.round(state.fillColor.a * o)

    case "stroke-opacity":
        var pos = 0'u64
        let o   = Math.saturate(scanNumber(value, &pos))
        state.strokeColor.a = cast(u8) Math.round(state.strokeColor.a * o)

    case "opacity":
        var pos = 0'u64
        state.opacity *= Math.saturate(scanNumber(value, &pos))

    case "stroke-width":
        var pos = 0'u64
        state.strokeWidth = scanNumber(value, &pos)

    case "fill-rule":
        state.evenOdd = value == "evenodd"

    case "stroke-linecap":
        switch value
        {
        case "round":  state.capStyle = .Round
        case "square": state.capStyle = .Square
        default:       state.capStyle = .None
        }

    case "stroke-linejoin":
        switch value
        {
        case "round": state.joinStyle = .Round
        case "bevel": state.joinStyle = .Bevel
        default:      state.joinStyle = .Miter
        }

    case "transform":
        var pos = 0'u64
        let len = @countof(value)
        while pos < len
        {
            while pos < len and (value[pos] == ' ' or value[pos] == ',') do
                pos += 1
            if pos + 9 < len and cast(string) @mkslice(@dataof(value) + pos, 9) == "translate"
            {
                pos += 9
                while pos < len and value[pos] != '(' do
                    pos += 1
                pos += 1
                let x    = scanNumber(value, &pos)
                var y    = 0'f32
                var look = pos
                while look < len and (value[look] == ' ' or value[look] == ',') do
                    look += 1
                if look < len and isNumberStart(value[look]) do
                    y = scanNumber(value, &pos)
                state.tx += x * state.sx
                state.ty += y * state.sy
                while pos < len and value[pos] != ')' do
                    pos += 1
                pos += 1
            }
            elif pos + 5 < len and cast(string) @mkslice(@dataof(value) + pos, 5) == "scale"
            {
                pos += 5
                while pos < len and value[pos] != '(' do
                    pos += 1
                pos += 1
                let x    = scanNumber(value, &pos)
                var y    = x
                var look = pos
                while look < len and (value[look] == ' ' or value[look] == ',') do
                    look += 1
                if look < len and isNumberStart(value[look]) do
                    y = scanNumber(value, &pos)
                state.sx *= x
                state.sy *= y
                while pos < len and value[pos] != ')' do
                    pos += 1
                pos += 1
            }
            else do
                break
        }
    }
}

private func applyAttribute(state: *GroupState, name, value: string)
{
    if name == "style"
    {
        // Inline declarations: name:value pairs separated by ';'.
        var scan = value
        while @countof(scan)
        {
            var stop = 0'u64
            while stop < @countof(scan) and scan[stop] != ';' do
                stop += 1
            let decl = @mkslice(@dataof(scan), stop)

            var sep = 0'u64
            while sep < @countof(decl) and decl[sep] != ':' do
                sep += 1
            if sep < @countof(decl)
            {
                var n = cast(string) @mkslice(@dataof(decl), sep)
                var v = cast(string) @mkslice(@dataof(decl) + sep + 1, @countof(decl) - sep - 1)
                n = Latin1.trim(n)
                v = Latin1.trim(v)
                applyStyleProperty(state, n, v)
            }

            if stop == @countof(scan) do
                break
            scan = cast(string) @mkslice(@dataof(scan) + stop + 1, @countof(scan) - stop - 1)
        }

        return
    }

    applyStyleProperty(state, name, value)
}

// Geometry /////////////////////////////////////////////////////////////////////

#[Swag.Inline]
private func mapX(state: *GroupState, x: f32) => x * state.sx + state.tx

#[Swag.Inline]
private func mapY(state: *GroupState, y: f32) => y * state.sy + state.ty

// Appends one endpoint-parameterized elliptical arc as cubic Béziers.
//
// `rotation` is out of contract and ignored; the themes never use it.
private func appendArc(path: *LinePath, x0, y0: f32, rxIn, ryIn: f32, largeArc, sweep: bool, x1, y1: f32)
{
    var rx = Math.abs(rxIn)
    var ry = Math.abs(ryIn)
    if rx <= 0.000001 or ry <= 0.000001 or (x0 == x1 and y0 == y1)
    {
        path.lineTo(x1, y1)
        return
    }

    // Endpoint to center parameterization (SVG specification appendix).
    let dx = (x0 - x1) * 0.5
    let dy = (y0 - y1) * 0.5

    var lambda = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry)
    if lambda > 1
    {
        lambda = Math.sqrt(lambda)
        rx     *= lambda
        ry     *= lambda
    }

    let rx2 = rx * rx
    let ry2 = ry * ry
    var num = rx2 * ry2 - rx2 * dy * dy - ry2 * dx * dx
    if num < 0 do
        num = 0
    let den  = rx2 * dy * dy + ry2 * dx * dx
    var coef = Math.sqrt(num / Math.max(den, 0.000001))
    if largeArc == sweep do
        coef = -coef

    let cx = coef * rx * dy / ry + (x0 + x1) * 0.5
    let cy = -coef * ry * dx / rx + (y0 + y1) * 0.5

    let startAngle = Math.atan2((y0 - cy) / ry, (x0 - cx) / rx)
    let endAngle   = Math.atan2((y1 - cy) / ry, (x1 - cx) / rx)

    var sweepAngle = endAngle - startAngle
    if sweep and sweepAngle < 0 do
        sweepAngle += 2 * Math.ConstF32.Pi
    elif !sweep and sweepAngle > 0 do
        sweepAngle -= 2 * Math.ConstF32.Pi

    // Split into segments no larger than a quarter turn and emit each as a cubic.
    let segCount = cast(s32) Math.max(Math.ceil(Math.abs(sweepAngle) / (Math.ConstF32.Pi * 0.5)), 1.0)
    let segAngle = sweepAngle / cast(f32) segCount
    let k        = 4.0 / 3.0 * Math.tan(segAngle * 0.25)

    var angle = startAngle
    for [i] in segCount
    {
        let a0  = angle
        let a1  = angle + segAngle
        let p0x = cx + rx * Math.cos(a0)
        let p0y = cy + ry * Math.sin(a0)
        let p1x = cx + rx * Math.cos(a1)
        let p1y = cy + ry * Math.sin(a1)
        let c0x = p0x - k * rx * Math.sin(a0)
        let c0y = p0y + k * ry * Math.cos(a0)
        let c1x = p1x + k * rx * Math.sin(a1)
        let c1y = p1y - k * ry * Math.cos(a1)
        path.bezierTo(p1x, p1y, c0x, c0y, c1x, c1y)
        angle = a1
    }
}

// Parses one `d` attribute into subpath contours, transformed by `state`.
private func parsePathData(list: *LinePathList, data: string, state: *GroupState)
{
    let len = @countof(data)
    var pos = 0'u64

    var cmd:        u8
    var curX, curY: f32     // Current point, user units.
    var begX, begY: f32     // Subpath start, user units.
    var ctlX, ctlY: f32     // Last cubic/quadratic control point, for S/T reflection.
    var lastCurve:  u8      // 'c' when the previous command was cubic-ish, 'q' for quadratic.

    var path:    #null *LinePath
    var started: bool

    func flag(data: string, pos: *u64)->bool
    {
        while dref pos < @countof(data) and (data[dref pos] == ' ' or data[dref pos] == ',') do
            dref pos += 1
        let f = dref pos < @countof(data) and data[dref pos] == '1'
        dref pos += 1
        return f
    }

    while pos < len
    {
        let c = data[pos]
        if c == ' ' or c == ',' or c == '\t' or c == '\n' or c == '\r'
        {
            pos += 1
            continue
        }

        if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')
        {
            cmd = c
            pos += 1
            if cmd == 'Z' or cmd == 'z'
            {
                if path and started do
                    path.close()
                curX      = begX
                curY      = begY
                started   = false
                lastCurve = 0
                continue
            }
        }
        elif !isNumberStart(c)
        {
            pos += 1
            continue
        }

        let rel = cmd >= 'a'
        switch cmd
        {
        case 'M', 'm':
            var x = scanNumber(data, &pos)
            var y = scanNumber(data, &pos)
            if rel
            {
                x += curX
                y += curY
            }

            path = list.newPath()
            path.start(mapX(state, x), mapY(state, y))
            started = true
            curX    = x
            curY    = y
            begX    = x
            begY    = y

            // Following coordinate pairs are implicit line-to commands.
            cmd = rel ? cast(u8) 'l' : cast(u8) 'L'

        case 'L', 'l':
            var x = scanNumber(data, &pos)
            var y = scanNumber(data, &pos)
            if rel
            {
                x += curX
                y += curY
            }

            // A zero-length segment adds a duplicate point, which degenerates the
            // fill tessellation; authored paths hit this when a radius equals half
            // the shape size.
            if Math.abs(x - curX) > 0.0005 or Math.abs(y - curY) > 0.0005 do
                path!.lineTo(mapX(state, x), mapY(state, y))
            curX = x
            curY = y

        case 'H', 'h':
            var x = scanNumber(data, &pos)
            if rel do
                x += curX
            path!.lineTo(mapX(state, x), mapY(state, curY))
            curX = x

        case 'V', 'v':
            var y = scanNumber(data, &pos)
            if rel do
                y += curY
            path!.lineTo(mapX(state, curX), mapY(state, y))
            curY = y

        case 'C', 'c', 'S', 's':
            var c1x, c1y: f32
            if cmd == 'C' or cmd == 'c'
            {
                c1x = scanNumber(data, &pos)
                c1y = scanNumber(data, &pos)
                if rel
                {
                    c1x += curX
                    c1y += curY
                }
            }
            else
            {
                // Reflect the previous cubic control point, or reuse the current point.
                c1x = curX
                c1y = curY
                if lastCurve == 'c'
                {
                    c1x = 2 * curX - ctlX
                    c1y = 2 * curY - ctlY
                }
            }

            var c2x = scanNumber(data, &pos)
            var c2y = scanNumber(data, &pos)
            var x   = scanNumber(data, &pos)
            var y   = scanNumber(data, &pos)
            if rel
            {
                c2x += curX
                c2y += curY
                x   += curX
                y   += curY
            }

            path!.bezierTo(mapX(state, x), mapY(state, y), mapX(state, c1x), mapY(state, c1y), mapX(state, c2x), mapY(state, c2y))
            ctlX      = c2x
            ctlY      = c2y
            curX      = x
            curY      = y
            lastCurve = 'c'
            continue

        case 'Q', 'q', 'T', 't':
            var c1x, c1y: f32
            if cmd == 'Q' or cmd == 'q'
            {
                c1x = scanNumber(data, &pos)
                c1y = scanNumber(data, &pos)
                if rel
                {
                    c1x += curX
                    c1y += curY
                }
            }
            else
            {
                c1x = curX
                c1y = curY
                if lastCurve == 'q'
                {
                    c1x = 2 * curX - ctlX
                    c1y = 2 * curY - ctlY
                }
            }

            var x = scanNumber(data, &pos)
            var y = scanNumber(data, &pos)
            if rel
            {
                x += curX
                y += curY
            }

            path!.bezierTo(mapX(state, x), mapY(state, y), mapX(state, c1x), mapY(state, c1y))
            ctlX      = c1x
            ctlY      = c1y
            curX      = x
            curY      = y
            lastCurve = 'q'
            continue

        case 'A', 'a':
            let rx = scanNumber(data, &pos)
            let ry = scanNumber(data, &pos)
            discard scanNumber(data, &pos)     // x-axis rotation, out of contract
            let largeArc = flag(data, &pos)
            let sweepF   = flag(data, &pos)
            var x        = scanNumber(data, &pos)
            var y        = scanNumber(data, &pos)
            if rel
            {
                x += curX
                y += curY
            }

            appendArc(path!, mapX(state, curX), mapY(state, curY), rx * state.sx, ry * state.sy, largeArc, sweepF, mapX(state, x), mapY(state, y))
            curX = x
            curY = y

        default:
            pos += 1
        }

        lastCurve = 0
    }
}

// Elements /////////////////////////////////////////////////////////////////////

private func emitShape(drawing: *Drawing, list: LinePathList, state: *GroupState)
{
    if list.paths.isEmpty() do
        return
    if !state.hasFill and !state.hasStroke do
        return

    // The triangulated fill treats every extra contour of a list as a hole cut into
    // the first, so a path whose contours are DISJOINT unions (an arrow above a bar)
    // would lose all but one region. Decompose by containment depth: every even-depth
    // contour roots its own shape and odd-depth contours join their root as holes.
    if state.hasFill and list.paths.count > 1
    {
        var work = #move list
        let n    = work.paths.count
        for p in work.paths do
            p.flatten(.Normal)

        var depth: Array's32
        depth.resize(n)
        for [i] in n
        {
            let pi = work.paths[i]
            if pi.polygon.points.count == 0 do
                continue
            let probe = pi.polygon.points[0]
            for [j] in n where j != i
            {
                if work.paths[j].polygon.contains(probe) do
                    depth[i] += 1
            }
        }

        var roots = 0
        for [i] in n where depth[i] % 2 == 0 do
            roots += 1

        if roots > 1
        {
            for [i] in n
            {
                if depth[i] % 2 != 0 do
                    continue

                var group: LinePathList
                group.paths.add(work.paths[i])
                let rootPoly = &work.paths[i].polygon

                // Attach this root's immediate holes.
                for [j] in n
                {
                    if depth[j] != depth[i] + 1 do
                        continue
                    let pj = work.paths[j]
                    if pj.polygon.points.count and rootPoly.contains(pj.polygon.points[0]) do
                        group.paths.add(pj)
                }

                emitShape(drawing, #move group, state)
            }

            // Every path pointer now belongs to a group list; forget them here.
            work.paths.clear()
            return
        }

        // Single root: emit as one shape below.
        emitShapeOne(drawing, #move work, state)
        return
    }

    emitShapeOne(drawing, #move list, state)
}

private func emitShapeOne(drawing: *Drawing, list: LinePathList, state: *GroupState)
{
    let shape = drawing.shapes.emplaceInitAddress()
    shape.pathList = #move list
    shape.hidden   = state.inDefs

    shape.hasFill = state.hasFill
    if state.hasFill
    {
        shape.fillColor   = state.fillColor
        shape.fillColor.a = cast(u8) Math.round(shape.fillColor.a * state.opacity)
        shape.evenOdd     = state.evenOdd
    }

    shape.hasStroke = state.hasStroke
    if state.hasStroke
    {
        shape.strokeColor   = state.strokeColor
        shape.strokeColor.a = cast(u8) Math.round(shape.strokeColor.a * state.opacity)
        shape.strokeWidth   = state.strokeWidth * state.sx
        shape.capStyle      = state.capStyle
        shape.joinStyle     = state.joinStyle
    }
}

private func emitRect(drawing: *Drawing, state: *GroupState, x, y, w, h, rx: f32)
{
    if w <= 0 or h <= 0 do
        return

    var list: LinePathList
    let path    = list.newPath()
    let halfMin = Math.min(w, h) * 0.5

    if rx >= halfMin - 0.001 and Math.abs(w - h) < 0.001
    {
        // A square with a full corner radius is a circle.
        path.setEllipseRaw(mapX(state, x + w * 0.5), mapY(state, y + h * 0.5), w * 0.5 * state.sx, h * 0.5 * state.sy)
    }
    elif rx > 0
    {
        let cr = Math.min(rx, halfMin)
        path.setRoundRectRaw(mapX(state, x), mapY(state, y), w * state.sx, h * state.sy, cr * state.sx, cr * state.sy)
    }
    else do
        path.setRectRaw(mapX(state, x), mapY(state, y), w * state.sx, h * state.sy)
    emitShape(drawing, list, state)
}

private func emitEllipse(drawing: *Drawing, state: *GroupState, cx, cy, rx, ry: f32)
{
    if rx <= 0 or ry <= 0 do
        return

    var list: LinePathList
    let path = list.newPath()
    path.setEllipseRaw(mapX(state, cx), mapY(state, cy), rx * state.sx, ry * state.sy)
    emitShape(drawing, list, state)
}

private func emitPoly(drawing: *Drawing, state: *GroupState, points: string, closeIt: bool)
{
    var list: LinePathList
    let path = list.newPath()
    var pos  = 0'u64
    var idx  = 0

    while pos < @countof(points)
    {
        var look = pos
        while look < @countof(points) and (points[look] == ' ' or points[look] == ',') do
            look += 1
        if look >= @countof(points) or !isNumberStart(points[look]) do
            break

        let x = scanNumber(points, &pos)
        let y = scanNumber(points, &pos)
        if idx == 0 do
            path.start(mapX(state, x), mapY(state, y))
        else do
            path.lineTo(mapX(state, x), mapY(state, y))
        idx += 1
    }

    if idx < 2 do
        return
    if closeIt do
        path.close()
    emitShape(drawing, list, state)
}

private impl Parser
{
    mtd skipUntil(c: u8)
    {
        let len = @countof(.text)
        while .pos < len and .text[.pos] != c do
            .pos += 1
    }

    // Scans the attributes of the current element into `state` and collects the
    // geometry attributes by name.
    mtd scanAttributes(state: *GroupState, geo: *HashTable'(String, String))->{ selfClosed: bool }
    {
        var result: retval
        let len = @countof(.text)

        while .pos < len
        {
            while .pos < len and (.text[.pos] == ' ' or .text[.pos] == '\t' or .text[.pos] == '\n' or .text[.pos] == '\r') do
                .pos += 1
            if .pos >= len do
                break

            if .text[.pos] == '/'
            {
                result.selfClosed = true
                .pos              += 1
                continue
            }

            if .text[.pos] == '>'
            {
                .pos += 1
                break
            }

            let nameStart = .pos
            while .pos < len and .text[.pos] != '=' and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' do
                .pos += 1
            let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)

            while .pos < len and .text[.pos] != '=' and .text[.pos] != '>' and .text[.pos] != '/' do
                .pos += 1
            if .pos >= len or .text[.pos] != '=' do
                continue
            .pos += 1

            while .pos < len and .text[.pos] != '"' and .text[.pos] != '\'' do
                .pos += 1
            if .pos >= len do
                break
            let quote = .text[.pos]
            .pos += 1
            let valueStart = .pos
            while .pos < len and .text[.pos] != quote do
                .pos += 1
            let value = cast(string) @mkslice(@dataof(.text) + valueStart, .pos - valueStart)
            .pos += 1

            switch name
            {
            case "d", "x", "y", "width", "height", "rx", "ry", "cx", "cy", "r", "points", "x1", "y1", "x2", "y2", "viewBox", "id", "href", "xlink:href": geo.add(name, value)
            default: applyAttribute(state, name, value)
            }
        }

        return result
    }

    mtd geoNumber(geo: *HashTable'(String, String), name: string, defaultValue = 0.0'f32)->f32
    {
        let here = geo.tryFind(name)
        if !here do
            return defaultValue
        var pos = 0'u64
        return scanNumber(here.value.toString(), &pos)
    }

    // Parses the elements between the current position and the parent's close tag.
    mtd parseContent(parent: GroupState) fail
    {
        let len = @countof(.text)
        while .pos < len
        {
            .skipUntil('<')
            if .pos >= len do
                return
            .pos += 1
            if .pos >= len do
                return

            // Closing tag of the parent scope.
            if .text[.pos] == '/'
            {
                .skipUntil('>')
                .pos += 1
                return
            }

            // Declarations and comments.
            if .text[.pos] == '?' or .text[.pos] == '!'
            {
                .skipUntil('>')
                .pos += 1
                continue
            }

            let nameStart = .pos
            while .pos < len and .text[.pos] != ' ' and .text[.pos] != '>' and .text[.pos] != '/' and .text[.pos] != '\t' and .text[.pos] != '\n' and .text[.pos] != '\r' do
                .pos += 1
            let name = cast(string) @mkslice(@dataof(.text) + nameStart, .pos - nameStart)

            var state        = parent
            var geo: HashTable'(String, String)
            let {selfClosed} = .scanAttributes(&state, &geo)
            let firstShape   = .drawing.shapes.count

            switch name
            {
            case "svg":
                let vb = geo.tryFind("viewBox")
                if vb
                {
                    var pos = 0'u64
                    discard scanNumber(vb.value.toString(), &pos)
                    discard scanNumber(vb.value.toString(), &pos)
                    .drawing.width  = scanNumber(vb.value.toString(), &pos)
                    .drawing.height = scanNumber(vb.value.toString(), &pos)
                }
                else
                {
                    .drawing.width  = .geoNumber(&geo, "width", 0)
                    .drawing.height = .geoNumber(&geo, "height", 0)
                }

                if !selfClosed do
                    try .parseContent(state)

            case "g":
                if !selfClosed do
                    try .parseContent(state)

            case "path":
                let d = geo.tryFind("d")
                if d
                {
                    var list: LinePathList
                    parsePathData(&list, d.value.toString(), &state)
                    emitShape(.drawing, list, &state)
                }

                if !selfClosed do
                    try .parseContent(state)

            case "rect":
                var rx = .geoNumber(&geo, "rx", -1)
                let ry = .geoNumber(&geo, "ry", -1)
                if rx < 0 do
                    rx = ry
                emitRect(.drawing, &state, .geoNumber(&geo, "x"), .geoNumber(&geo, "y"), .geoNumber(&geo, "width"), .geoNumber(&geo, "height"), Math.max(rx, 0))
                if !selfClosed do
                    try .parseContent(state)

            case "circle":
                let r = .geoNumber(&geo, "r")
                emitEllipse(.drawing, &state, .geoNumber(&geo, "cx"), .geoNumber(&geo, "cy"), r, r)
                if !selfClosed do
                    try .parseContent(state)

            case "ellipse":
                emitEllipse(.drawing, &state, .geoNumber(&geo, "cx"), .geoNumber(&geo, "cy"), .geoNumber(&geo, "rx"), .geoNumber(&geo, "ry"))
                if !selfClosed do
                    try .parseContent(state)

            case "line":
                var list: LinePathList
                let path = list.newPath()
                path.start(mapX(&state, .geoNumber(&geo, "x1")), mapY(&state, .geoNumber(&geo, "y1")))
                path.lineTo(mapX(&state, .geoNumber(&geo, "x2")), mapY(&state, .geoNumber(&geo, "y2")))
                var strokeOnly = state
                strokeOnly.hasFill = false
                emitShape(.drawing, list, &strokeOnly)
                if !selfClosed do
                    try .parseContent(state)

            case "defs":

                // Definitions are parsed in local coordinates and withheld from
                // painting; `use` elements instantiate them.
                var defState: GroupState
                defState.inDefs = true
                if !selfClosed do
                    try .parseContent(defState)

            case "use":
                var href = geo.tryFind("href")
                if !href do
                    href = geo.tryFind("xlink:href")
                if href
                {
                    var name2 = href.value.toString()
                    if @countof(name2) and name2[0] == '#' do
                        name2 = cast(string) @mkslice(@dataof(name2) + 1, @countof(name2) - 1)
                    let here = .defs.tryFind(name2)
                    if here do
                        .instantiate(here.value.first, here.value.count, &state, .geoNumber(&geo, "x"), .geoNumber(&geo, "y"))
                }

                if !selfClosed do
                    try .parseContent(state)

            case "polygon":
                let pts = geo.tryFind("points")
                if pts do
                    emitPoly(.drawing, &state, pts.value.toString(), true)
                if !selfClosed do
                    try .parseContent(state)

            case "polyline":
                let pts = geo.tryFind("points")
                if pts
                {
                    var strokeOnly = state
                    strokeOnly.hasFill = false
                    emitPoly(.drawing, &strokeOnly, pts.value.toString(), false)
                }

                if !selfClosed do
                    try .parseContent(state)

            default:

                // Unknown element: ignore it and its whole subtree.
                if !selfClosed do
                    try .parseContent(state)
            }

            // Register the shapes a defs child emitted under its id.
            if state.inDefs and .drawing.shapes.count > firstShape
            {
                let idAttr = geo.tryFind("id")
                if idAttr do
                    .defs.add(idAttr.value, {firstShape, .drawing.shapes.count - firstShape})
            }
        }
    }

    // Appends transformed copies of a definition's shapes.
    mtd instantiate(first, count: u64, state: *GroupState, offX, offY: f32)
    {
        for [i] in count
        {
            // Build the transformed copy fully before appending: appending can
            // reallocate the array and invalidate the source borrow.
            var list:                        LinePathList
            var fillColor, strokeColor:      Color
            var hasFill, hasStroke, evenOdd: bool
            var strokeWidth:                 f32
            var capStyle:                    LineCapStyle = None
            var joinStyle:                   JoinStyle    = Miter

            {
                let src = &.drawing.shapes[first + i]
                fillColor   = src.fillColor
                strokeColor = src.strokeColor
                hasFill     = src.hasFill
                hasStroke   = src.hasStroke
                evenOdd     = src.evenOdd
                strokeWidth = src.strokeWidth * state.sx
                capStyle    = src.capStyle
                joinStyle   = src.joinStyle

                for srcPath in src.pathList.paths
                {
                    let path = list.newPath()
                    path.start(mapX(state, srcPath.startPoint.x + offX), mapY(state, srcPath.startPoint.y + offY))
                    for &element in srcPath.elements
                    {
                        switch element.type
                        {
                        case .Line:
                            path.lineTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY))

                        case .Bezier1:
                            path.bezierTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY), mapX(state, element.p1.x + offX), mapY(state, element.p1.y + offY))

                        case .Bezier2:
                            path.bezierTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY), mapX(state, element.p1.x + offX), mapY(state, element.p1.y + offY), mapX(state, element.p2.x + offX), mapY(state, element.p2.y + offY))

                        case .Arc:

                            // An arc stores its center in `position`, its angle
                            // interval in `p1`, and its radii in `p2`.
                            path.arcTo(mapX(state, element.position.x + offX), mapY(state, element.position.y + offY), element.p2.x * state.sx, element.p2.y * state.sy, Math.Angle.fromRadians(element.p1.x), Math.Angle.fromRadians(element.p1.y))

                        default:
                            Debug.assert(false, "definition uses an unsupported segment type")
                        }
                    }

                    if srcPath.isClosed do
                        path.close()
                }
            }

            let shape = .drawing.shapes.emplaceInitAddress()
            shape.pathList    = #move list
            shape.fillColor   = fillColor
            shape.strokeColor = strokeColor
            shape.hasFill     = hasFill
            shape.hasStroke   = hasStroke
            shape.evenOdd     = evenOdd
            shape.strokeWidth = strokeWidth
            shape.capStyle    = capStyle
            shape.joinStyle   = joinStyle
            shape.hidden      = state.inDefs
        }
    }
}

impl Drawing
{
    // Returns the number of parsed shapes.
    mtd const shapeCount()->u64 => .shapes.count

    // Parses an SVG document authored in the supported subset.
    //
    // The result owns its shapes and can be painted concurrently from const
    // borrows. Unknown elements and attributes are ignored.
    func parse(text: string)->Drawing fail
    {
        var result: retval

        var parser = Parser{text: text, drawing: &result}

        var root: GroupState
        try parser.parseContent(root)

        if result.width <= 0 or result.height <= 0 do
            fail Swag.SystemError{"SVG document has no valid dimensions"}

        return result
    }

    // Paints the drawing with its origin at `(x, y)` of the current path space,
    // its content multiplied by `scale`.
    //
    // Fills honor the winding of their contours (a counter-clockwise contour is a
    // hole), strokes honor width, caps, and joins scaled by `scale`.
    mtd const paint(painter: *Painter, x, y: f32, scale = 1.0'f32)
    {
        .paintImpl(painter, x, y, scale, false)
    }

    // The alpha-preserving resolve of a `paintAlpha` render target squares fragment
    // alpha (GL_MAX with a source-alpha factor; the CPU renderer matches it). Painting
    // with square-rooted shape alphas makes that resolve land back on the authored
    // values; with supersampling, per-sample coverage is essentially binary, so the
    // compensation is exact in practice.
    internal mtd const paintImpl(painter: *Painter, x, y: f32, scale: f32, compensateAlpha: bool)
    {
        painter.pushState()
        defer painter.popState()

        // Local drawing space: scale then translate, applied before the current transform.
        var tr = Math.Transform2.createScale(scale, scale, 0, 0)
        tr.multiply(Math.Transform2.createTranslation(x, y))
        tr.multiply(painter.transform())
        painter.setTransform(tr)

        for &shape in .shapes
        {
            if shape.hidden do
                continue

            if shape.hasFill
            {
                var fc = shape.fillColor
                if compensateAlpha do
                    fc.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) fc.a / 255.0))
                painter.fillPath(&shape.pathList, fc)
            }

            if shape.hasStroke
            {
                var sc = shape.strokeColor
                if compensateAlpha do
                    sc.a = cast(u8) Math.round(255.0 * Math.sqrt(cast(f32) sc.a / 255.0))
                var pen = Pen.createSolid(sc, shape.strokeWidth)
                pen.begCapStyle = shape.capStyle
                pen.endCapStyle = shape.capStyle
                pen.joinStyle   = shape.joinStyle
                painter.drawPath(&shape.pathList, pen, .Separate)
            }
        }
    }

    // Rasterizes the drawing into an owned image of exactly `width` by `height` pixels.
    //
    // The drawing is scaled uniformly from its view box to `width`, antialiased, on
    // a transparent ground. Rasterization is done in software: no window, no GPU.
    //
    // `supersample` renders that many samples per axis and box-filters them down,
    // replacing the renderer's screen-space edge feather with near-exact coverage.
    // The default doubles sampling, a good balance for icon and atlas work.
    //
    // An application that already owns a renderer should pass it to the overload
    // below instead: filling the supersampled buffer is the whole cost here, and a
    // GPU backend does it in a fraction of the time.
    mtd const rasterize(width, height: s32, supersample: u8 = 2)->Image
    {
        Debug.assert(width > 0 and height > 0)

        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        cpu.begin(width, height)
        var result = .rasterize(renderer, width, height, supersample)
        renderer.end()
        return result
    }

    // Rasterizes the drawing through `renderer` into an owned image of exactly
    // `width` by `height` pixels.
    //
    // The result is identical whichever backend produces it, up to the raster-edge
    // tolerance the two backends already carry elsewhere. Both the supersampled pass
    // and its downsample happen inside the renderer, so no supersampled buffer ever
    // crosses back to the caller: only the finished image does.
    //
    // The renderer must be ready to draw — its context selected and [[Pixel.IRenderer.init]]
    // called — because this records a complete painter submission and executes it.
    mtd const rasterize(renderer: IRenderer, width, height: s32, supersample: u8 = 2)->Image
    {
        Debug.assert(width > 0 and height > 0)

        let ss = cast(s32) Math.max(supersample, 1'u8)
        let bw = width * ss
        let bh = height * ss

        // Targets are created at the exact size instead of acquired from the pool, which
        // rounds up to a power of two: the resolve reads the sampled target as a whole,
        // and padding would land inside the box filter.
        var sampled = renderer.createRenderTarget(bw, bh)
        var resolved: RenderTarget
        if ss > 1 do
            resolved = renderer.createRenderTarget(width, height)

        // Antialiased and translucent shapes go through the overlap-safe pass, which
        // sacrifices the destination alpha channel; render into a target with the
        // alpha-preserving replay so the result carries a correct alpha mask.
        var painter = Painter.create(renderer)
        painter.begin()
        painter.bindRenderTarget(&sampled, paintAlpha: true)
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.Zero))
        painter.setColorMaskColor()
        .paintImpl(&painter, 0, 0, cast(f32) bw / .width, true)
        painter.unbindRenderTarget()

        // Box-filter the samples down with the renderer's own resolve program, the one
        // the layer pipeline already uses. Unbinding above has resolved the alpha plane,
        // so the sampled target is a plain texture by the time it is read here.
        if ss > 1
        {
            let dstRect = Math.Rectangle{0, 0, cast(f32) width, cast(f32) height}
            let srcRect = Math.Rectangle{0, 0, cast(f32) bw, cast(f32) bh}
            painter.bindRenderTarget(&resolved)
            painter.setResolveShader(ss)
            painter.setColorMaskFull()
            painter.setBlendingMode(.Copy)
            painter.clear(Color.fromArgb(Argb.Zero))
            painter.drawTexture(dstRect, srcRect, sampled.colorBuffer)
            painter.setDefaultShader()
            painter.unbindRenderTarget()
        }

        painter.end()
        renderer.draw(&painter)

        // Render-target readbacks follow the bottom-up row convention, which is also
        // the storage convention of [[Pixel.Image]] buffers, so the readback is kept
        // as is: flipping here would make the drawing render upside down as a texture.
        if ss == 1
        {
            var only = renderer.readRenderTarget(&sampled, 0, 0, bw, bh)
            renderer.deleteRenderTarget(&sampled)
            return only
        }

        var result = renderer.readRenderTarget(&resolved, 0, 0, width, height)
        renderer.deleteRenderTarget(&resolved)
        renderer.deleteRenderTarget(&sampled)

        // The resolve leaves a fully transparent pixel black; make it white instead, so a
        // consumer that tints the result, or a sampler that interpolates across the edge
        // of a shape, never blends a dark fringe in.
        result.setTransparentColor(Color.fromArgb(Argb.White))
        return result
    }
}

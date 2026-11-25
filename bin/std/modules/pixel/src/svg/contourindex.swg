#global internal
#global namespace Svg

using Core, Core.Math

const MinIndexedContours = 64

private struct ContourBounds
{
    min, max: Vector2
}

private impl ContourBounds
{
    mtd const combined(other: ContourBounds)->ContourBounds
    {
        return {Vector2.min(.min, other.min), Vector2.max(.max, other.max)}
    }

    mtd const overlaps(other: ContourBounds)->bool =>
        .min.x <= other.max.x and
        .max.x >= other.min.x and
        .min.y <= other.max.y and
        .max.y >= other.min.y
}

private struct ContourNode
{
    bounds:       ContourBounds
    first, count: u64
    right:        u64
}

// Bounds filter the candidates for the SVG containment tests. Entries keep their authored indices.
struct ContourIndex
{
    private
    {
        bounds:    Array'ContourBounds
        order:     Array'u64
        nodes:     Array'ContourNode
        matches:   Array'u64
    }
}

impl ContourIndex
{
    mtd build(paths: const *LinePathList)
    {
        let count = paths.paths.count
        .order.reserve(count)
        for i in count do
            .order.add(i)

        // The exact ray test interpolates x in f32. Keep a margin for rounding and use the
        // original search when coordinates or edge differences make this bound unreliable.
        const Limit = 1e30'f32
        .bounds.resize(count)
        for path, index in paths.paths
        {
            let points = &path.polygon.points
            if points.isEmpty() do
                continue

            var box   = ContourBounds{points[0], points[0]}
            var prevY = points.back().y
            for i in points.count
            {
                let point = points[i]
                if not Math.isFinite(point.x) or
                   not Math.isFinite(point.y) or
                   Math.abs(point.x) > Limit or
                   Math.abs(point.y) > Limit do
                    return
                if point.y != prevY and Math.abs(point.y - prevY) < Swag.F32.MinNormal do
                    return
                prevY   = point.y
                box.min = Vector2.min(box.min, point)
                box.max = Vector2.max(box.max, point)
            }

            let magnitude = Math.max(Math.abs(box.min.x), Math.abs(box.max.x))
            let margin    = Math.max(magnitude * 0.000001, 1e-30)
            box.min.x      -= margin
            box.max.x      += margin
            .bounds[index] = box
        }

        var total = .bounds[0]
        for i in 1 until count do
            total = total.combined(.bounds[i])

        let bounds = .bounds.toSlice()
        let sortX  = total.max.x - total.min.x >= total.max.y - total.min.y
        .order.sort(func|bounds, sortX|(a, b: u64)->s32
        {
            let amin       = bounds[a].min
            let bmin       = bounds[b].min
            let comparison = sortX ? amin.x <=> bmin.x : amin.y <=> bmin.y
            if comparison do
                return comparison
            return sortX ? amin.y <=> bmin.y : amin.x <=> bmin.x
        })
        discard .buildNode(0, count)
    }

    private mtd buildNode(first, count: u64)->u64
    {
        let index = .nodes.count
        .nodes.add(ContourNode{first: first, count: count})

        if count <= 12
        {
            var box = .bounds[.order[first]]
            for offset in 1 until count do
                box = box.combined(.bounds[.order[first + offset]])
            .nodes[index].bounds = box
            return index
        }

        let half  = count / 2
        let left  = .buildNode(first, half)
        let right = .buildNode(first + half, count - half)
        .nodes[index].bounds = .nodes[left].bounds.combined(.nodes[right].bounds)
        .nodes[index].right  = right
        return index
    }

    private mtd appendOverlaps(index: u64, query: ContourBounds)
    {
        let node = &.nodes[index]
        if not node.bounds.overlaps(query) do
            return
        if node.right
        {
            // The left child is stored immediately after its parent.
            .appendOverlaps(index + 1, query)
            .appendOverlaps(node.right, query)
            return
        }

        for offset in node.count
        {
            let pathIndex = .order[node.first + offset]
            if .bounds[pathIndex].overlaps(query) do
                .matches.add(pathIndex)
        }
    }

    #[Swag.Inline]
    mtd candidateContainers(point: Vector2)->const [..] u64
    {
        if .nodes.isEmpty() do
            return .order.toSlice()
        .matches.clear()
        .appendOverlaps(0, {min: point, max: point})
        return .matches.toSlice()
    }

    #[Swag.Inline]
    mtd candidateHoles(pathIndex: u64)->const [..] u64
    {
        if .nodes.isEmpty() do
            return .order.toSlice()
        .matches.clear()
        .appendOverlaps(0, .bounds[pathIndex])
        .matches.sort()
        return .matches.toSlice()
    }
}

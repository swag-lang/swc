// @LICENCE: BSD-3-Clause
// @ORIGIN: Poly2Tri, https://github.com/jhasse/poly2tri
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#poly2tri

#global namespace Poly2Tri

using Core

enum Orientation
{
    CW
    CCW
    Collinear
}

// Owns the working state for constrained Delaunay triangulation.
//
// Treat this type as opaque and use its tessellation entry points. The returned
// [[Pixel.Poly2Tri.Result]] owns the flattened triangle vertices.
//
// ## Example
//
// ```swag
// var polygon: Pixel.Polygon
// polygon.add(Math.Vector2{0, 0})
// polygon.add(Math.Vector2{100, 0})
// polygon.add(Math.Vector2{50, 80})
// polygon.add(Math.Vector2{0, 0}) // Close the ring.
// polygon.recompute()
//
// var tessellator: Pixel.Poly2Tri.Tessellate
// tessellator.addPolyLine(polygon)
// tessellator.triangulate()
// let triangles = tessellator.takeResult().vertices
// ```
#[Swag.Opaque]
#[Swag.NoCopy]
public struct Tessellate
{
    // Sweep-line state of one tessellation: the advancing front, the node pool, and the
    // graph being built. Read the outcome from 'Result', never from here.

    private
    {
        basin:     Basin         // Basin being filled by the current sweep event.
        edgeEvent: EdgeEvent     // Constrained edge the current sweep event follows.

        triangles:  Array!{*Triangle}     // Triangles produced so far.
        edges:      Array!{*Edge}         // Constrained edges of the input.
        points:     Array!{*Point}        // Points of the input, in sweep order.
        triIndices: Array!{u64}           // Flat triples indexing 'points'.

        nodes: Array!{*Node}     // Node pool of the advancing front.

        // Objects returned by 'clear' and handed back out by the next tessellation.
        freeNodes:     Array!{*Node}
        freePoints:    Array!{*Point}
        freeEdges:     Array!{*Edge}
        freeTriangles: Array!{*Triangle}

        // Where every registered point sits on a grid of coincidence-sized cells, so that
        // registering one asks the nine cells that could hold a match rather than the whole
        // point set. See 'dupRegister'.
        dupCells: HashTable!{u64, u32}     // Cell key to the first slot filed in it.
        dupNext:  Array!{u32}              // Slot to the next slot filed in the same cell.
        dupPoint: Array!{*Point?}          // Slot to its point, or null once forgotten.

        front:     AdvancingFront     // The advancing front itself.
        head:      *Point?            // Left artificial point of the front.
        tail:      *Point?            // Right artificial point of the front.
        afHead:    *Node?             // Node holding 'head'.
        afMiddle:  *Node?             // Node the sweep last searched from.
        afTail:    *Node?             // Node holding 'tail'.
        polyStart: u64                // Index the current polygon starts at in 'points'.

        failedSweep: bool     // A constrained edge could not be inserted safely.
    }
}

// Owns the triangle vertices produced by one tessellation.
public struct Result
{
    public vertices: Array!{Math.Vector2}     // Triangle vertices stored as consecutive triples.
}

// Stores one tessellation point and its incident constrained edges.
struct Point
{
    using v: Math.Vector2      // Point coordinates in path space.
    edges:   Array!{*Edge}     // Incident constrained edges.
    border:  [2] (*Edge?)      // Up to two boundary edges.
}

// Connects two tessellation points with a constrained edge.
struct Edge
{
    late p: *Point     // Lower endpoint according to Poly2Tri ordering.
    late q: *Point     // Upper endpoint according to Poly2Tri ordering.
}

// Stores one triangle and its adjacency/classification state.
struct Triangle
{
    constrainedEdge: [3] bool             // Whether each opposite edge is constrained.
    delaunayEdge:    [3] bool             // Temporary Delaunay edge markers.
    points:          [3] *Point           // Counter-clockwise triangle vertices.
    neighbors:       [3] (*Triangle?)     // Adjacent triangles opposite each point.
    idx:             u64                  // Result-local triangle index.
    interior:        bool                 // Whether the triangle belongs to the output interior.
}

struct EdgeEvent
{
    constrainedEdge: *Edge?
    right: bool
}

struct Basin
{
    leftNode:    *Node?
    bottomNode:  *Node?
    rightNode:   *Node?
    width:       f64
    leftHighest: bool
}

struct Node
{
    late point:    *Point
    late triangle: *Triangle
    next:          *Node?
    prev:          *Node?
    value:         f64
}

struct AdvancingFront
{
    head: *Node?
    tail: *Node?
    late searchNode: *Node
}

func nnPoint(p: *Point?)->*Point => unwrap p

func nnNode(n: *Node?)->*Node => unwrap n

func nnTriangle(t: *Triangle?)->*Triangle => unwrap t

impl Result
{
    // Returns the number of triangles in the result.
    public mtd triangleCount()->u64 => .vertices.count / 3

    // Removes all triangle vertices.
    mtd clear() { .vertices.clear() }
}

impl Edge
{
    mtd set(p1, p2: *Point)
    {
        .p = p1
        .q = p2
        if p1.y > p2.y
        {
            .q = p1
            .p = p2
        }
        else if p1.y == p2.y
        {
            if p1.x > p2.x
            {
                .q = p1
                .p = p2
            }
            else if p1.x == p2.x
            {
                Swag.assert(false, "Edge::Edge: p1 == p2")
            }
        }

        .q.edges.add(me)
        if .p.border[0]
        {
            .p.border[1] = me
        }
        else
        {
            .p.border[0] = me
        }

        if .q.border[0]
        {
            .q.border[1] = me
        }
        else
        {
            .q.border[0] = me
        }
    }
}

impl Triangle
{
    mtd markConstrainedEdge(index: s32)
    {
        .constrainedEdge[index] = true
    }

    mtd markConstrainedEdge(edge: *Edge)
    {
        .markConstrainedEdge(edge.p, edge.q)
    }

    mtd markConstrainedEdge(p, q: *Point)
    {
        if (q == .points[0] and p == .points[1]) or (q == .points[1] and p == .points[0])
        {
            .constrainedEdge[2] = true
        }
        else if (q == .points[0] and p == .points[2]) or (q == .points[2] and p == .points[0])
        {
            .constrainedEdge[1] = true
        }
        else if (q == .points[1] and p == .points[2]) or (q == .points[2] and p == .points[1])
        {
            .constrainedEdge[0] = true
        }
    }

    mtd oppositePoint(t: *Triangle, p: *Point)->*Point
    {
        let cw = t.pointCW(p)
        return .pointCW(cw)
    }

    // Index of the edge whose endpoints are 'p1' and 'p2', or -1 if 'p1'/'p2' are
    // not both vertices of this triangle. Callers (e.g. isEdgeSideOfTriangle) rely
    // on the -1 result, so this must not go through the asserting .index().
    mtd edgeIndex(p1, p2: *Point)->s32
    {
        if p1 == .points[0]
        {
            if p2 == .points[1]
            {
                return 2
            }

            if p2 == .points[2]
            {
                return 1
            }
        }
        else if p1 == .points[1]
        {
            if p2 == .points[2]
            {
                return 0
            }

            if p2 == .points[0]
            {
                return 2
            }
        }
        else if p1 == .points[2]
        {
            if p2 == .points[0]
            {
                return 1
            }

            if p2 == .points[1]
            {
                return 0
            }
        }

        return -1
    }

    mtd index(p: *Point)->s32
    {
        if p == .points[0]
        {
            return 0
        }

        if p == .points[1]
        {
            return 1
        }

        if p == .points[2]
        {
            return 2
        }

        Swag.assert(false)
        return -1
    }

    mtd neighborAcross(point: *Point)->*Triangle?
    {
        let idx = .index(point)
        if idx == 0
        {
            return .neighbors[0]
        }

        if idx == 1
        {
            return .neighbors[1]
        }

        if idx == 2
        {
            return .neighbors[2]
        }

        Swag.assert(false)
        return null
    }

    mtd neighborCW(point: *Point)->*Triangle?
    {
        let idx = .index(point)
        if idx == 0
        {
            return .neighbors[1]
        }

        if idx == 1
        {
            return .neighbors[2]
        }

        if idx == 2
        {
            return .neighbors[0]
        }

        Swag.assert(false)
        return null
    }

    mtd neighborCCW(p: *Point)->*Triangle?
    {
        let idx = .index(p)
        if idx == 0
        {
            return .neighbors[2]
        }

        if idx == 1
        {
            return .neighbors[0]
        }

        if idx == 2
        {
            return .neighbors[1]
        }

        Swag.assert(false)
        return null
    }

    mtd getConstrainedEdgeCCW(p: *Point)->bool
    {
        let idx = .index(p)
        if idx == 0
        {
            return .constrainedEdge[2]
        }

        if idx == 1
        {
            return .constrainedEdge[0]
        }

        if idx == 2
        {
            return .constrainedEdge[1]
        }

        Swag.assert(false)
        return false
    }

    mtd getConstrainedEdgeCW(p: *Point)->bool
    {
        let idx = .index(p)
        if idx == 0
        {
            return .constrainedEdge[1]
        }

        if idx == 1
        {
            return .constrainedEdge[2]
        }

        if idx == 2
        {
            return .constrainedEdge[0]
        }

        Swag.assert(false)
        return false
    }

    mtd pointCW(point: *Point)->*Point
    {
        let idx = .index(point)
        if idx == 0
        {
            return .points[2]
        }

        if idx == 1
        {
            return .points[0]
        }

        if idx == 2
        {
            return .points[1]
        }

        Swag.assert(false)
        return cast(*Point, 1_u64)
    }

    mtd pointCCW(point: *Point)->*Point
    {
        let idx = .index(point)
        if idx == 0
        {
            return .points[1]
        }

        if idx == 1
        {
            return .points[2]
        }

        if idx == 2
        {
            return .points[0]
        }

        Swag.assert(false)
        return cast(*Point, 1_u64)
    }

    mtd getDelaunayEdgeCCW(p: *Point)->bool
    {
        let idx = .index(p)
        if idx == 0
        {
            return .delaunayEdge[2]
        }

        if idx == 1
        {
            return .delaunayEdge[0]
        }

        if idx == 2
        {
            return .delaunayEdge[1]
        }

        Swag.assert(false)
        return false
    }

    mtd getDelaunayEdgeCW(p: *Point)->bool
    {
        let idx = .index(p)
        if idx == 0
        {
            return .delaunayEdge[1]
        }

        if idx == 1
        {
            return .delaunayEdge[2]
        }

        if idx == 2
        {
            return .delaunayEdge[0]
        }

        Swag.assert(false)
        return false
    }

    mtd setDelaunayEdgeCCW(p: *Point, e: bool)
    {
        let idx = .index(p)
        if idx == 0
        {
            .delaunayEdge[2] = e
            return
        }

        if idx == 1
        {
            .delaunayEdge[0] = e
            return
        }

        if idx == 2
        {
            .delaunayEdge[1] = e
            return
        }

        Swag.assert(false)
    }

    mtd setDelaunayEdgeCW(p: *Point, e: bool)
    {
        let idx = .index(p)
        if idx == 0
        {
            .delaunayEdge[1] = e
            return
        }

        if idx == 1
        {
            .delaunayEdge[2] = e
            return
        }

        if idx == 2
        {
            .delaunayEdge[0] = e
            return
        }

        Swag.assert(false)
    }

    mtd setConstrainedEdgeCCW(p: *Point, ce: bool)
    {
        let idx = .index(p)
        if idx == 0
        {
            .constrainedEdge[2] = ce
            return
        }

        if idx == 1
        {
            .constrainedEdge[0] = ce
            return
        }

        if idx == 2
        {
            .constrainedEdge[1] = ce
            return
        }

        Swag.assert(false)
    }

    mtd setConstrainedEdgeCW(p: *Point, ce: bool)
    {
        let idx = .index(p)
        if idx == 0
        {
            .constrainedEdge[1] = ce
            return
        }

        if idx == 1
        {
            .constrainedEdge[2] = ce
            return
        }

        if idx == 2
        {
            .constrainedEdge[0] = ce
            return
        }

        Swag.assert(false)
    }

    mtd clearNeighbors()
    {
        .neighbors[0] = null
        .neighbors[1] = null
        .neighbors[2] = null
    }

    mtd clearDelaunayEdges()
    {
        .delaunayEdge[0] = false
        .delaunayEdge[1] = false
        .delaunayEdge[2] = false
    }

    mtd contains(p: *Point)->bool => p == .points[0] or p == .points[1] or p == .points[2]

    mtd contains(p1, p2: *Point)->bool => .contains(p1) and .contains(p2)

    mtd markNeighbor(p1, p2: *Point, t: *Triangle)
    {
        if (p1 == .points[2] and p2 == .points[1]) or (p1 == .points[1] and p2 == .points[2])
        {
            .neighbors[0] = t
        }
        else if (p1 == .points[0] and p2 == .points[2]) or (p1 == .points[2] and p2 == .points[0])
        {
            .neighbors[1] = t
        }
        else if (p1 == .points[0] and p2 == .points[1]) or (p1 == .points[1] and p2 == .points[0])
        {
            .neighbors[2] = t
        }
        else
        {
            Swag.assert(false)
        }
    }

    mtd markNeighbor(t: *Triangle)
    {
        if t.contains(.points[1], .points[2])
        {
            .neighbors[0] = t
            t.markNeighbor(.points[1], .points[2], me)
        }
        else if t.contains(.points[0], .points[2])
        {
            .neighbors[1] = t
            t.markNeighbor(.points[0], .points[2], me)
        }
        else if t.contains(.points[0], .points[1])
        {
            .neighbors[2] = t
            t.markNeighbor(.points[0], .points[1], me)
        }
    }

    mtd legalize(opoint, npoint: *Point)
    {
        let idx = .index(opoint)
        if idx == 0
        {
            .points[1] = .points[0]
            .points[0] = .points[2]
            .points[2] = npoint
            return
        }

        if idx == 1
        {
            .points[2] = .points[1]
            .points[1] = .points[0]
            .points[0] = npoint
            return
        }

        if idx == 2
        {
            .points[0] = .points[2]
            .points[2] = .points[1]
            .points[1] = npoint
            return
        }

        Swag.assert(false)
    }
}

impl AdvancingFront
{
    mtd locatePoint(point: *Point)->*Node?
    {
        let px           = point.x
        let start        = nnNode(.searchNode)
        var node: *Node? = start
        let nx           = start.point.x

        if px == nx
        {
            if point != start.point
            {
                if point == nnNode(start.prev).point
                {
                    node = start.prev
                }
                else if point == nnNode(start.next).point
                {
                    node = start.next
                }
                else
                {
                    Swag.assert(false)
                }
            }
        }
        else if px < nx
        {
            node = start.prev
            while node
            {
                if point == node.point
                {
                    break
                }

                node = node.prev
            }
        }
        else
        {
            node = start.next
            while node
            {
                if point == node.point
                {
                    break
                }

                node = node.next
            }
        }

        if node
        {
            .searchNode = nnNode(node)
        }

        return node
    }

    mtd locateNode(x: f32)->*Node
    {
        let start        = nnNode(.searchNode)
        var node: *Node? = start
        if x < start.value
        {
            node = start.prev
            while node
            {
                if x >= node.value
                {
                    .searchNode = nnNode(node)
                    return nnNode(node)
                }

                node = node.prev
            }
        }
        else
        {
            node = start.next
            while node
            {
                if x < node.value
                {
                    .searchNode = nnNode(node.prev)
                    return nnNode(node.prev)
                }

                node = node.next
            }
        }

        unreachable
    }
}

impl Tessellate
{
    // Releases all working geometry and cached sweep nodes owned by the tessellator.
    public mtd opDrop()
    {
        .clear()
        .clearCache()
    }

    // The sweep allocates one object per input point, per constrained edge and per triangle it
    // builds, and [[Pixel.Poly2Tri.Tessellate.clear]] hands every one of them back between two
    // tessellations. Releasing them to the allocator instead would make a page of vector art pay
    // millions of allocation pairs — a document whose thousands of paths are tessellated once
    // spends more time freeing sweep state than sweeping. Every kind is therefore pooled the way
    // the front nodes already were: `clear` returns them, the next tessellation takes them back,
    // and [[Pixel.Poly2Tri.Tessellate.clearCache]] is what actually releases them. Because `clear`
    // empties the working arrays each time, a pool only ever holds what the largest single
    // tessellation needed, never what a whole document allocated.
    #[Swag.Inline]
    {
        mtd newPoint()->*Point
        {
            if .freePoints.count
            {
                let p = .freePoints.popBack()

                // A point owns its incident-edge array, so it is reset field by field rather
                // than re-initialized: clearing keeps the storage the next ring will refill.
                p.v         = {}
                p.border[0] = null
                p.border[1] = null
                p.edges.clear()
                return p
            }

            return Memory.new!{Point}()
        }

        mtd deletePoint(ptr: *Point)
        {
            .freePoints.add(ptr)
        }

        mtd newEdge()->*Edge
        {
            // Both endpoints are written by 'Edge.set' before the edge is used, which is why a
            // recycled edge needs no reset and a fresh one leaves them undefined.
            if .freeEdges.count
            {
                return .freeEdges.popBack()
            }

            return Memory.new!{Edge}()
        }

        mtd deleteEdge(ptr: *Edge)
        {
            .freeEdges.add(ptr)
        }

        // A triangle names its three vertices, so it is built rather than default-initialized:
        // its point array has no null to start from, and every other field is result state the
        // sweep fills as it goes.
        mtd newTriangle(a, b, c: *Point)->*Triangle
        {
            var target: *Triangle
            if .freeTriangles.count
            {
                target = .freeTriangles.popBack()
            }
            else
            {
                target = cast(*Triangle, Memory.alloc(#sizeof(Triangle)))
            }

            target[] = Triangle{points: [a, b, c]}
            return target
        }

        mtd deleteTriangle(ptr: *Triangle)
        {
            .freeTriangles.add(ptr)
        }

        mtd newNode()->*Node
        {
            if .freeNodes.count
            {
                let p = .freeNodes.popBack()
                Swag.init(p, 1)
                return p
            }

            return Memory.new!{Node}()
        }

        mtd deleteNode(ptr: *Node)
        {
            .freeNodes.add(ptr)
        }
    }

    // Discards the registered polylines and the last triangulation, keeping pooled storage.
    public mtd clear()
    {
        Swag.init(&.basin, 1)
        Swag.init(&.edgeEvent, 1)
        .polyStart   = 0
        .failedSweep = false

        if .head
        {
            .deletePoint(nnPoint(.head))
        }

        if .tail
        {
            .deletePoint(nnPoint(.tail))
        }

        if .afHead
        {
            .deleteNode(nnNode(.afHead))
        }

        if .afMiddle
        {
            .deleteNode(nnNode(.afMiddle))
        }

        if .afTail
        {
            .deleteNode(nnNode(.afTail))
        }

        .head, .tail, .afHead, .afMiddle, .afTail = null

        for p in .points
        {
            .deletePoint(p)
        }

        for p in .edges
        {
            .deleteEdge(p)
        }

        for p in .triangles
        {
            .deleteTriangle(p)
        }

        for p in .nodes
        {
            .deleteNode(p)
        }

        .points.clear()
        .edges.clear()
        .triangles.clear()
        .triIndices.clear()
        .nodes.clear()
        .dupClear()
    }

    // Releases the pooled sweep objects a cleared tessellator is still holding.
    mtd clearCache()
    {
        for p in .freeNodes
        {
            Memory.delete(p)
        }

        for p in .freePoints
        {
            Memory.delete(p)
        }

        for p in .freeEdges
        {
            Memory.delete(p)
        }

        for p in .freeTriangles
        {
            Memory.delete(p)
        }

        .freeNodes.clear()
        .freePoints.clear()
        .freeEdges.clear()
        .freeTriangles.clear()
    }

    // Transfers the triangulation result out of this tessellator.
    //
    // The tessellator remains reusable after the transfer. Its point, edge,
    // triangle, and index arrays are empty until new input is added.
    public mtd takeResult()->Result
    {
        var result: #returntype
        result.vertices.reserve(.triIndices.count * 3)
        for triangleIndex in .triIndices
        {
            let triangle = .triangles[triangleIndex]
            result.vertices.add(triangle.points[0].v)
            result.vertices.add(triangle.points[1].v)
            result.vertices.add(triangle.points[2].v)
        }

        .clear()
        return result
    }

    // Two points closer than this in both axes are the same vertex as far as the sweep is
    // concerned, and the grid cell is sized to match so a candidate can only be in the nine
    // cells around the one it lands in.
    const CoincidentDistance = 0.0005_f32

    // Returns the grid column or row a coordinate falls in.
    //
    // The clamp is what keeps a wild coordinate — a path built from an unchecked transform —
    // from converting to an out-of-range integer; two such points landing in the same clamped
    // cell only costs an extra exact comparison.
    #[Swag.Inline]
    private func dupCellCoord(value: f32)->s32 => cast(s32, Math.floor(Math.clamp(value / CoincidentDistance, -1.0e9, 1.0e9)))

    #[Swag.Inline]
    private func dupCellKey(cx, cy: s32)->u64 => (cast(u64, cast #bit (u32, cx)) << 32) | cast(u64, cast #bit (u32, cy))

    // Files one registered point in its cell.
    //
    // A chain link is a slot index biased by one, so that the zero a fresh table entry starts
    // life with reads as the end of the chain rather than as slot zero pointing at itself.
    private mtd dupRegister(p: *Point)
    {
        let entry = .dupCells.findOrAdd(dupCellKey(dupCellCoord(p.x), dupCellCoord(p.y)))
        .dupPoint.add(p)
        .dupNext.add(entry.value)
        entry.value = cast(u32, .dupPoint.count)
    }

    // Drops one point from its cell, so a point the ring cleanup removed stops matching.
    private mtd dupForget(p: *Point)
    {
        let entry = .dupCells.tryFind(dupCellKey(dupCellCoord(p.x), dupCellCoord(p.y)))
        if not entry
        {
            return
        }

        var link = entry.value
        while link
        {
            if .dupPoint[link - 1] == p
            {
                .dupPoint[link - 1] = null
                return
            }

            link = .dupNext[link - 1]
        }
    }

    // Whether a point within the coincidence distance of `(x, y)` is already registered.
    private mtd dupContains(x, y: f32)->bool
    {
        if .dupPoint.isEmpty()
        {
            return false
        }

        let cx = dupCellCoord(x)
        let cy = dupCellCoord(y)
        for dy in -1 to 1
        {
            for dx in -1 to 1
            {
                let entry = .dupCells.tryFind(dupCellKey(cx + dx, cy + dy))
                if not entry
                {
                    continue
                }

                var link = entry.value
                while link
                {
                    let other = .dupPoint[link - 1]
                    if other and
                       Math.abs(x - other.x) < CoincidentDistance and
                       Math.abs(y - other.y) < CoincidentDistance
                    {
                        return true
                    }

                    link = .dupNext[link - 1]
                }
            }
        }

        return false
    }

    // Reuses coincidence cells that are still proportionate to the last border set.
    private mtd dupClear()
    {
        if .dupCells.capacity > 256 and .dupCells.capacity / 8 > .dupCells.count do
            .dupCells.free()
        else do
            .dupCells.clear()
        .dupNext.clear()
        .dupPoint.clear()
    }

    // Starts registering one closed polygon border.
    //
    // Add its points with [[Pixel.Poly2Tri.Tessellate.addPoint]], then close it with
    // [[Pixel.Poly2Tri.Tessellate.endPolyLine]].
    public mtd startPolyLine()
    {
        .polyStart = .points.count
    }

    // Adds one point to the polygon border being registered.
    public mtd addPoint(pt: Math.Vector2)
    {
        let p = .newPoint()
        p.x = pt.x
        p.y = pt.y
        .points.add(p)
        .dupRegister(p)
    }

    // Closes the polygon border started by [[Pixel.Poly2Tri.Tessellate.startPolyLine]].
    //
    // Coincident consecutive points and zero-area spikes are dropped from the border.
    public mtd endPolyLine()
    {
        mtd initEdges(polyline: [..] *Point)
        {
            for pt, i in polyline
            {
                let nexti = (i + 1) % polyline.count
                let edge  = .newEdge()
                edge.set(pt, polyline[nexti])
                .edges.add(edge)
            }
        }

        // The sweep rejects rings that carry coincident consecutive points or
        // zero-area spikes (A, B, A), and authored outlines do contain both; drop
        // them until the ring is clean. A spike bounds no area, so removing it never
        // changes the fill.
        func closeEnough(a, b: *Point)->bool => Math.abs(a.x - b.x) < CoincidentDistance and Math.abs(a.y - b.y) < CoincidentDistance

        // A dropped point leaves the ring for good: it is unfiled from the coincidence grid so
        // it stops matching, and returned to the pool rather than left behind.
        mtd dropPoint(index: u64)
        {
            let p = .points[index]
            .dupForget(p)
            .points.removeAtOrdered(index)
            .deletePoint(p)
        }

        var i = 0_u64
        while .points.count - .polyStart >= 3
        {
            let count = .points.count - .polyStart
            if i >= count
            {
                break
            }

            let cur  = .points[.polyStart + i]
            let next = .points[.polyStart + (i + 1) % count]
            let prev = .points[.polyStart + (i + count - 1) % count]
            if closeEnough(cur, next)
            {
                dropPoint(me, .polyStart + (i + 1) % count)
                i = 0
            }
            else if closeEnough(prev, next)
            {
                // Remove the spike tip and one of its equal ends.
                let tip = .polyStart + i
                let end = .polyStart + (i + 1) % count
                dropPoint(me, Math.max(tip, end))
                dropPoint(me, Math.min(tip, end))
                i = 0
            }
            else
            {
                i += 1
            }
        }

        if .points.count - .polyStart < 3
        {
            while .points.count > .polyStart
            {
                dropPoint(me, .points.count - 1)
            }

            .polyStart = .points.count
            return
        }

        // A ring can retain three distinct points and still enclose no area.
        var twiceArea = 0_f64
        var previous  = .points[.points.count - 1]
        for i in .polyStart to .points.count - 1
        {
            let current = .points[i]
            twiceArea += cast(f64, previous.x) * cast(f64, current.y) - cast(f64, current.x) * cast(f64, previous.y)
            previous  = current
        }

        if Math.isZeroEpsilon(twiceArea)
        {
            while .points.count > .polyStart
            {
                dropPoint(me, .points.count - 1)
            }

            .polyStart = .points.count
            return
        }

        initEdges(me, .points[.polyStart to .points.count - 1])
    }

    // Registers the points of `poly` as one closed polygon border. A repeated final point that is
    // within half a pixel of the first is treated as the closing endpoint and omitted. Borders
    // with fewer than three points are ignored; zero-area borders are ignored when the line closes.
    public mtd addPolyLine(poly: Polygon)
    {
        .points.grow(.points.count + poly.points.count)

        var count = poly.points.count
        if count > 1 and poly.points[0].distanceSquaredTo(poly.points[count - 1]) < 0.5 * 0.5
        {
            count -= 1
        }

        if count < 3
        {
            return
        }

        // Poly2Tri cannot represent two constraints that share a vertex. PDF glyph-like paths
        // nevertheless use touching holes, so separate a repeated point by one thousandth of a
        // path-space pixel toward the contour it belongs to. The perturbation is subpixel even
        // at extreme display scales and turns an undefined topology into the intended tiny
        // bridge of fill between the holes.
        var center: Math.Vector2
        for i in count
        {
            center += poly.points[i]
        }

        if count
        {
            center /= cast(f32, count)
        }

        .startPolyLine()
        for i in count
        {
            let p  = .newPoint()
            var pt = poly.points[i]
            if .dupContains(pt.x, pt.y)
            {
                var direction = Math.Vector2.normalizedOrZero(center - pt)
                if direction.isEqualEpsilon({})
                {
                    direction = {1, 0}
                }

                pt += direction * 0.001
            }

            p.x = pt.x
            p.y = pt.y
            .points.add(p)
            .dupRegister(p)
        }

        .endPolyLine()
    }

    // Triangulates every registered border; read the triangles with [[Pixel.Poly2Tri.Tessellate.takeResult]].
    public mtd triangulate()
    {
        if .points.isEmpty()
        {
            return
        }

        .initTriangulation()
        .createAdvancingFront()
        .sweepPoints()
        if .failedSweep
        {
            return
        }

        .finalizationPolygon()

        .points.add(nnPoint(.head))
        .points.add(nnPoint(.tail))
        .head = null
        .tail = null
    }

    internal mtd const sweepFailed()->bool => .failedSweep

    mtd sweepPoints()
    {
        for i in 1 until .points.count
        {
            let point = .points[i]
            let node  = .pointEvent(point)
            for e in point.edges
            {
                .addEdgeEvent2(e, node)
                if .failedSweep
                {
                    return
                }
            }
        }
    }

    mtd addEdgeEvent(ep, eq: *Point, triangle: *Triangle?, point: *Point)
    {
        if .failedSweep
        {
            return
        }

        if not triangle
        {
            .failedSweep = true
            return
        }

        if isEdgeSideOfTriangle(triangle, ep, eq)
        {
            return
        }

        let p1 = triangle.pointCCW(point)
        let o1 = orient2d(eq, p1, ep)
        if o1 == .Collinear
        {
            if triangle.contains(eq, p1)
            {
                triangle.markConstrainedEdge(eq, p1)
                .edgeEvent.constrainedEdge!.q = p1
                .addEdgeEvent(ep, p1, triangle.neighborAcross(point), p1)
            }
            else
            {
                Swag.assert(false, "EdgeEvent - collinear points not supported")
            }

            return
        }

        let p2 = triangle.pointCW(point)
        let o2 = orient2d(eq, p2, ep)
        if o2 == .Collinear
        {
            if triangle.contains(eq, p2)
            {
                triangle.markConstrainedEdge(eq, p2)
                .edgeEvent.constrainedEdge!.q = p2
                .addEdgeEvent(ep, p2, triangle.neighborAcross(point), p2)
            }
            else
            {
                Swag.assert(false, "EdgeEvent - collinear points not supported")
            }

            return
        }

        if o1 == o2
        {
            let neighbor = o1 == .CW ? triangle.neighborCCW(point) : triangle.neighborCW(point)
            .addEdgeEvent(ep, eq, neighbor, point)
        }
        else
        {
            .flipEdgeEvent(ep, eq, triangle, point)
        }
    }

    mtd flipEdgeEvent(ep, eq: *Point, tri: *Triangle, p: *Point)
    {
        var t  = tri
        let ot = t.neighborAcross(p)
        if not ot
        {
            .failedSweep = true
            return
        }

        let op = ot.oppositePoint(t, p)

        if inScanArea(p, t.pointCCW(p), t.pointCW(p), op)
        {
            rotateTrianglePair(t, p, ot, op)
            .mapTriangleToNodes(t)
            .mapTriangleToNodes(ot)

            if p == eq and op == ep
            {
                let constrainedEdge = unwrap .edgeEvent.constrainedEdge
                if eq == constrainedEdge.q and ep == constrainedEdge.p
                {
                    t.markConstrainedEdge(ep, eq)
                    ot.markConstrainedEdge(ep, eq)
                    discard .legalize(t)
                    discard .legalize(ot)
                }
            }
            else
            {
                let o = orient2d(eq, op, ep)
                t = .nextFlipTriangle(o, t, ot, p, op)
                .flipEdgeEvent(ep, eq, t, p)
            }
        }
        else
        {
            let newP = nextFlipPoint(ep, eq, ot, op)
            .flipScanEdgeEvent(ep, eq, t, ot, newP)
            .addEdgeEvent(ep, eq, t, p)
        }
    }

    mtd nextFlipTriangle(o: Orientation, t, ot: *Triangle, p, op: *Point)->*Triangle
    {
        if o == .CCW
        {
            let edgeIndex = ot.edgeIndex(p, op)
            ot.delaunayEdge[edgeIndex] = true
            discard .legalize(ot)
            ot.clearDelaunayEdges()
            return t
        }

        let edgeIndex = t.edgeIndex(p, op)
        t.delaunayEdge[edgeIndex] = true
        discard .legalize(t)
        t.clearDelaunayEdges()
        return ot
    }

    func nextFlipPoint(ep, eq: *Point, ot: *Triangle, op: *Point)->*Point
    {
        let o2d = orient2d(eq, op, ep)
        if o2d == .CW
        {
            return ot.pointCCW(op)
        }

        Swag.assert(o2d == .CCW, "[Unsupported] Opposing point on constrained edge")
        return ot.pointCW(op)
    }

    mtd flipScanEdgeEvent(ep, eq: *Point, flipTriangle: *Triangle, t: *Triangle, p: *Point)
    {
        let ot = t.neighborAcross(p)
        if not ot
        {
            .failedSweep = true
            return
        }

        let op = ot.oppositePoint(t, p)
        let p1 = flipTriangle.pointCCW(eq)
        let p2 = flipTriangle.pointCW(eq)
        if inScanArea(eq, p1, p2, op)
        {
            .flipEdgeEvent(eq, op, ot, op)
        }
        else
        {
            let newP = nextFlipPoint(ep, eq, ot, op)
            .flipScanEdgeEvent(ep, eq, flipTriangle, ot, newP)
        }
    }

    mtd addEdgeEvent2(edge: *Edge, node: *Node)
    {
        .edgeEvent.constrainedEdge = edge
        .edgeEvent.right = edge.p.x > edge.q.x

        if isEdgeSideOfTriangle(node.triangle, edge.p, edge.q)
        {
            return
        }

        .fillEdgeEvent(edge, node)
        .addEdgeEvent(edge.p, edge.q, node.triangle, edge.q)
    }

    mtd fillEdgeEvent(edge: *Edge, node: *Node)
    {
        if .edgeEvent.right
        {
            .fillRightAboveEdgeEvent(edge, node)
        }
        else
        {
            .fillLeftAboveEdgeEvent(edge, node)
        }
    }

    mtd fillRightAboveEdgeEvent(edge: *Edge, n: *Node)
    {
        var node = n
        while not .failedSweep and node.next and node.next.point.x < edge.p.x
        {
            let adjacent = node.next
            if orient2d(edge.q, adjacent.point, edge.p) == .CCW
            {
                let before = .triangles.count
                .fillRightBelowEdgeEvent(edge, node)
                if .triangles.count == before
                {
                    return
                }
            }
            else
            {
                node = adjacent
            }
        }
    }

    mtd fillRightBelowEdgeEvent(edge: *Edge, node: *Node)
    {
        if not .failedSweep and node.point.x < edge.p.x
        {
            let next = node.next
            if not next or not next.next
            {
                .failedSweep = true
                return
            }

            if orient2d(node.point, next.point, next.next.point) == .CCW
            {
                .fillRightConcaveEdgeEvent(edge, node)
            }
            else
            {
                let before = .triangles.count
                .fillRightConvexEdgeEvent(edge, node)
                if .triangles.count != before
                {
                    .fillRightBelowEdgeEvent(edge, node)
                }
            }
        }
    }

    mtd fillRightConcaveEdgeEvent(edge: *Edge, node: *Node)
    {
        let remove = node.next
        if not remove or not remove.next
        {
            .failedSweep = true
            return
        }

        .fill(remove)
        let next = node.next
        if next and next.next and next.point != edge.p
        {
            if orient2d(edge.q, next.point, edge.p) == .CCW
            {
                if orient2d(node.point, next.point, next.next.point) == .CCW
                {
                    .fillRightConcaveEdgeEvent(edge, node)
                }
            }
        }
    }

    mtd fillRightConvexEdgeEvent(edge: *Edge, node: *Node)
    {
        let next = node.next
        if not next
        {
            return
        }

        let nextNext = next.next
        if not nextNext or not nextNext.next
        {
            return
        }

        if orient2d(next.point, nextNext.point, nextNext.next.point) == .CCW
        {
            .fillRightConcaveEdgeEvent(edge, next)
        }
        else
        {
            if orient2d(edge.q, nextNext.point, edge.p) == .CCW
            {
                .fillRightConvexEdgeEvent(edge, next)
            }
        }
    }

    mtd fillLeftAboveEdgeEvent(edge: *Edge, n: *Node)
    {
        var node = n
        while not .failedSweep and node.prev and node.prev.point.x > edge.p.x
        {
            let adjacent = node.prev
            if orient2d(edge.q, adjacent.point, edge.p) == .CW
            {
                let before = .triangles.count
                .fillLeftBelowEdgeEvent(edge, node)
                if .triangles.count == before
                {
                    return
                }
            }
            else
            {
                node = adjacent
            }
        }
    }

    mtd fillLeftBelowEdgeEvent(edge: *Edge, node: *Node)
    {
        if not .failedSweep and node.point.x > edge.p.x
        {
            let prev = node.prev
            if not prev or not prev.prev
            {
                .failedSweep = true
                return
            }

            if orient2d(node.point, prev.point, prev.prev.point) == .CW
            {
                .fillLeftConcaveEdgeEvent(edge, node)
            }
            else
            {
                let before = .triangles.count
                .fillLeftConvexEdgeEvent(edge, node)
                if .triangles.count != before
                {
                    .fillLeftBelowEdgeEvent(edge, node)
                }
            }
        }
    }

    mtd fillLeftConvexEdgeEvent(edge: *Edge, node: *Node)
    {
        let prev = node.prev
        if not prev
        {
            return
        }

        let prevPrev = prev.prev
        if not prevPrev or not prevPrev.prev
        {
            return
        }

        if orient2d(prev.point, prevPrev.point, prevPrev.prev.point) == .CW
        {
            .fillLeftConcaveEdgeEvent(edge, prev)
        }
        else
        {
            if orient2d(edge.q, prevPrev.point, edge.p) == .CW
            {
                .fillLeftConvexEdgeEvent(edge, prev)
            }
        }
    }

    mtd fillLeftConcaveEdgeEvent(edge: *Edge, node: *Node)
    {
        let remove = node.prev
        if not remove or not remove.prev
        {
            .failedSweep = true
            return
        }

        .fill(remove)
        let prev = node.prev
        if prev and prev.prev and prev.point != edge.p
        {
            if orient2d(edge.q, prev.point, edge.p) == .CW
            {
                if orient2d(node.point, prev.point, prev.prev.point) == .CW
                {
                    .fillLeftConcaveEdgeEvent(edge, node)
                }
            }
        }
    }

    func isEdgeSideOfTriangle(triangle: *Triangle, ep, eq: *Point)->bool
    {
        let index = triangle.edgeIndex(ep, eq)
        if index != -1
        {
            triangle.markConstrainedEdge(index)
            let t = triangle.neighbors[index]
            t?.markConstrainedEdge(ep, eq)
            return true
        }

        return false
    }

    mtd pointEvent(point: *Point)->*Node
    {
        let node = .locateNode(point)
        Swag.assert(node.next != null, "null node")
        let newNode = .newFrontTriangle(point, node)

        // Point coordinates are f32; compare with an f32 epsilon so the test stays in single
        // precision (mixing an f64 epsilon here promotes the f32 operands to f64).
        if point.x <= node.point.x + Math.ConstF32.Epsilon
        {
            .fill(nnNode(node))
        }

        .fillAdvancingFront(newNode)
        return newNode
    }

    mtd fillAdvancingFront(n: *Node)
    {
        var node = n.next
        while node and node.next
        {
            if largeHoleDontFill(nnNode(node))
            {
                break
            }

            .fill(nnNode(node))
            node = nnNode(node.next)
        }

        node = n.prev
        while node and node.prev
        {
            if largeHoleDontFill(nnNode(node))
            {
                break
            }

            .fill(nnNode(node))
            node = nnNode(node.prev)
        }

        let nnext = n.next
        if nnext and nnext.next
        {
            let angle = basinAngle(n)
            if angle < Math.ConstF64.ThreePiBy4
            {
                .fillBasin(n)
            }
        }
    }

    mtd fillBasin(node: *Node)
    {
        let next = nnNode(node.next)
        if orient2d(node.point, next.point, nnNode(next.next).point) == .CCW
        {
            .basin.leftNode = next.next
        }
        else
        {
            .basin.leftNode = node.next
        }

        let leftNode   = nnNode(.basin.leftNode)
        var bottomNode = leftNode
        while bottomNode.next and bottomNode.point.y >= nnNode(bottomNode.next).point.y
        {
            bottomNode = nnNode(bottomNode.next)
        }

        .basin.bottomNode = bottomNode
        if bottomNode == leftNode
        {
            return
        }

        var rightNode = bottomNode
        while rightNode.next and rightNode.point.y < nnNode(rightNode.next).point.y
        {
            rightNode = nnNode(rightNode.next)
        }

        .basin.rightNode = rightNode
        if rightNode == bottomNode
        {
            return
        }

        .basin.width       = rightNode.point.x - leftNode.point.x
        .basin.leftHighest = leftNode.point.y > rightNode.point.y

        .fillBasinReq(bottomNode)
    }

    mtd fillBasinReq(n: *Node)
    {
        var node = n
        if .isShallow(node)
        {
            return
        }

        .fill(nnNode(node))

        if node.prev == .basin.leftNode and node.next == .basin.rightNode
        {
            return
        }

        if node.prev == .basin.leftNode
        {
            let next = nnNode(node.next)
            let o    = orient2d(node.point, next.point, nnNode(next.next).point)
            if o == .CW
            {
                return
            }

            node = next
        }
        else if node.next == .basin.rightNode
        {
            let prev = nnNode(node.prev)
            let o    = orient2d(node.point, prev.point, nnNode(prev.prev).point)
            if o == .CCW
            {
                return
            }

            node = prev
        }
        else
        {
            if nnNode(node.prev).point.y < nnNode(node.next).point.y
            {
                node = nnNode(node.prev)
            }
            else
            {
                node = nnNode(node.next)
            }
        }

        .fillBasinReq(node)
    }

    mtd isShallow(node: *Node)->bool
    {
        var height: f64
        if .basin.leftHighest
        {
            height = nnNode(.basin.leftNode).point.y - node.point.y
        }
        else
        {
            height = nnNode(.basin.rightNode).point.y - node.point.y
        }

        return .basin.width > height
    }

    func basinAngle(node: *Node)->f64
    {
        let nextNext = nnNode(nnNode(node.next).next)
        let ax       = node.point.x - nextNext.point.x
        let ay       = node.point.y - nextNext.point.y
        return Math.atan2(ay, ax)
    }

    func largeHoleDontFill(node: *Node)->bool
    {
        let nextNode = nnNode(node.next)
        let prevNode = nnNode(node.prev)
        if not angleExceeds90Degrees(node.point, nextNode.point, prevNode.point)
        {
            return false
        }

        if angleIsNegative(node.point, nextNode.point, prevNode.point)
        {
            return true
        }

        let next2Node = nextNode.next
        if next2Node and not angleExceedsPlus90DegreesOrIsNegative(node.point, next2Node.point, prevNode.point)
        {
            return false
        }

        let prev2Node = prevNode.prev
        if prev2Node and not angleExceedsPlus90DegreesOrIsNegative(node.point, nextNode.point, prev2Node.point)
        {
            return false
        }

        return true
    }

    func angleIsNegative(origin, pa, pb: *Point)->bool
    {
        let angle = angle(origin, pa, pb)
        return angle < 0
    }

    func angleExceeds90Degrees(origin, pa, pb: *Point)->bool
    {
        let angle = angle(origin, pa, pb)
        return (angle > Math.ConstF64.PiBy2) or (angle < -Math.ConstF64.PiBy2)
    }

    func angleExceedsPlus90DegreesOrIsNegative(origin, pa, pb: *Point)->bool
    {
        let angle = angle(origin, pa, pb)
        return (angle > Math.ConstF64.PiBy2) or (angle < 0)
    }

    func angle(origin, pa, pb: *Point)->f64
    {
        let px = origin.x
        let py = origin.y
        let ax = pa.x - px
        let ay = pa.y - py
        let bx = pb.x - px
        let by = pb.y - py
        let x  = ax * by - ay * bx
        let y  = ax * bx + ay * by
        return Math.atan2(x, y)
    }

    mtd fill(node: *Node)
    {
        let prev     = nnNode(node.prev)
        let next     = nnNode(node.next)
        let triangle = .newTriangle(prev.point, node.point, next.point)

        triangle.markNeighbor(prev.triangle)
        triangle.markNeighbor(node.triangle)

        triangle.idx = .triangles.count
        .triangles.add(triangle)

        prev.next = node.next
        next.prev = node.prev

        if not .legalize(triangle)
        {
            .mapTriangleToNodes(triangle)
        }
    }

    mtd newFrontTriangle(point: *Point, node: *Node)->*Node
    {
        let oldNext  = nnNode(node.next)
        let triangle = .newTriangle(point, node.point, oldNext.point)

        triangle.markNeighbor(node.triangle)

        triangle.idx = .triangles.count
        .triangles.add(triangle)

        let newNode = .newNode()
        newNode.point = point
        newNode.value = point.x
        .nodes.add(newNode)

        newNode.next = node.next
        newNode.prev = node
        oldNext.prev = newNode
        node.next    = newNode

        if not .legalize(triangle)
        {
            .mapTriangleToNodes(triangle)
        }

        return newNode
    }

    func orient2d(pa, pb, pc: *Point)->Orientation
    {
        let detleft  = (pa.x - pc.x) * (pb.y - pc.y)
        let detright = (pa.y - pc.y) * (pb.x - pc.x)
        let val      = detleft - detright
        if Math.isZeroEpsilon(val)
        {
            return Orientation.Collinear
        }

        if val > 0
        {
            return Orientation.CCW
        }

        return Orientation.CW
    }

    func inScanArea(pa, pb, pc, pd: *Point)->bool
    {
        let oadb = (pa.x - pb.x) * (pd.y - pb.y) - (pd.x - pb.x) * (pa.y - pb.y)
        if oadb >= -Math.ConstF64.Epsilon
        {
            return false
        }

        let oadc = (pa.x - pc.x) * (pd.y - pc.y) - (pd.x - pc.x) * (pa.y - pc.y)
        if oadc <= Math.ConstF64.Epsilon
        {
            return false
        }

        return true
    }

    func incircle(pa, pb, pc, pd: *Point)->bool
    {
        let adx = pa.x - pd.x
        let ady = pa.y - pd.y
        let bdx = pb.x - pd.x
        let bdy = pb.y - pd.y

        let adxbdy = adx * bdy
        let bdxady = bdx * ady
        let oabd   = adxbdy - bdxady

        if oabd <= 0
        {
            return false
        }

        let cdx = pc.x - pd.x
        let cdy = pc.y - pd.y

        let cdxady = cdx * ady
        let adxcdy = adx * cdy
        let ocad   = cdxady - adxcdy

        if ocad <= 0
        {
            return false
        }

        let bdxcdy = bdx * cdy
        let cdxbdy = cdx * bdy

        let alift = adx * adx + ady * ady
        let blift = bdx * bdx + bdy * bdy
        let clift = cdx * cdx + cdy * cdy

        let det = alift * (bdxcdy - cdxbdy) + blift * ocad + clift * oabd
        return det > 0
    }

    mtd legalize(t: *Triangle)->bool
    {
        for i in 3
        {
            if t.delaunayEdge[i]
            {
                continue
            }

            let ot = t.neighbors[i]
            if ot
            {
                let p  = t.points[i]
                let op = ot.oppositePoint(t, p)
                let oi = ot.index(op)

                if ot.constrainedEdge[oi] or ot.delaunayEdge[oi]
                {
                    t.constrainedEdge[i] = ot.constrainedEdge[oi]
                    continue
                }

                let inside = incircle(p, t.pointCCW(p), t.pointCW(p), op)
                if inside
                {
                    t.delaunayEdge[i]   = true
                    ot.delaunayEdge[oi] = true

                    let safeOt = nnTriangle(ot)
                    rotateTrianglePair(t, p, safeOt, op)

                    var notLegalized = not .legalize(t)
                    if notLegalized
                    {
                        .mapTriangleToNodes(t)
                    }

                    notLegalized = not .legalize(safeOt)
                    if notLegalized
                    {
                        .mapTriangleToNodes(safeOt)
                    }

                    t.delaunayEdge[i]   = false
                    ot.delaunayEdge[oi] = false
                    return true
                }
            }
        }

        return false
    }

    func rotateTrianglePair(t: *Triangle, p: *Point, ot: *Triangle, op: *Point)
    {
        let n1 = t.neighborCCW(p)
        let n2 = t.neighborCW(p)
        let n3 = ot.neighborCCW(op)
        let n4 = ot.neighborCW(op)

        let ce1 = t.getConstrainedEdgeCCW(p)
        let ce2 = t.getConstrainedEdgeCW(p)
        let ce3 = ot.getConstrainedEdgeCCW(op)
        let ce4 = ot.getConstrainedEdgeCW(op)

        let de1 = t.getDelaunayEdgeCCW(p)
        let de2 = t.getDelaunayEdgeCW(p)
        let de3 = ot.getDelaunayEdgeCCW(op)
        let de4 = ot.getDelaunayEdgeCW(op)

        t.legalize(p, op)
        ot.legalize(op, p)

        ot.setDelaunayEdgeCCW(p, de1)
        t.setDelaunayEdgeCW(p, de2)
        t.setDelaunayEdgeCCW(op, de3)
        ot.setDelaunayEdgeCW(op, de4)

        ot.setConstrainedEdgeCCW(p, ce1)
        t.setConstrainedEdgeCW(p, ce2)
        t.setConstrainedEdgeCCW(op, ce3)
        ot.setConstrainedEdgeCW(op, ce4)

        t.clearNeighbors()
        ot.clearNeighbors()
        if n1
        {
            ot.markNeighbor(nnTriangle(n1))
        }

        if n2
        {
            t.markNeighbor(nnTriangle(n2))
        }

        if n3
        {
            t.markNeighbor(nnTriangle(n3))
        }

        if n4
        {
            ot.markNeighbor(nnTriangle(n4))
        }

        t.markNeighbor(ot)
    }

    mtd mapTriangleToNodes(t: *Triangle)
    {
        for i in 3
        {
            if not t.neighbors[i]
            {
                let n = .front.locatePoint(t.pointCW(t.points[i]))
                if n
                {
                    n.triangle = t
                }
            }
        }
    }

    mtd locateNode(point: *Point)->*Node => .front.locateNode(point.x)

    mtd finalizationPolygon()
    {
        let headNext      = nnNode(nnNode(.front.head).next)
        var t: *Triangle? = headNext.triangle
        let p             = headNext.point
        while t and not t.getConstrainedEdgeCW(p)
        {
            t = t.neighborCCW(p)
        }

        if t
        {
            .meshClean(t)
        }
    }

    mtd meshClean(triangle: *Triangle)
    {
        var stack: Array!{*Triangle?}
        stack.add(triangle)

        .triIndices.clear()

        while stack.count
        {
            let t = stack.popBack()
            if not t or t.interior
            {
                continue
            }

            t.interior = true
            .triIndices.add(t.idx)

            if not t.constrainedEdge[0]
            {
                stack.add(t.neighbors[0])
            }

            if not t.constrainedEdge[1]
            {
                stack.add(t.neighbors[1])
            }

            if not t.constrainedEdge[2]
            {
                stack.add(t.neighbors[2])
            }
        }

        // Remove neighbors which are not part of the mesh
        for i in .triIndices
        {
            let tri = .triangles[i]
            for e in 3
            {
                let neighbor = tri.neighbors[e]
                if neighbor and not neighbor.interior
                {
                    tri.neighbors[e] = null
                }
            }
        }
    }

    mtd initTriangulation()
    {
        var xmin, xmax = .points[0].x
        var ymin, ymax = .points[0].y
        for p in .points
        {
            xmax = Math.max(xmax, p.x)
            xmin = Math.min(xmin, p.x)
            ymax = Math.max(ymax, p.y)
            ymin = Math.min(ymin, p.y)
        }

        const KAlpha = 0.3_f32
        let dx = KAlpha * (xmax - xmin)
        let dy = KAlpha * (ymax - ymin)
        .head   = .newPoint()
        .head.x = xmin - dx
        .head.y = ymin - dy
        .tail   = .newPoint()
        .tail.x = xmax + dx
        .tail.y = ymin - dy

        func cmp(a, b: *Point)->s32
        {
            if a.y < b.y
            {
                return -1
            }

            if a.y > b.y
            {
                return 1
            }

            if a.x < b.x
            {
                return -1
            }

            if a.x > b.x
            {
                return 1
            }

            return 0
        }

        Slice.sort(.points.toSlice(), &cmp)
    }

    mtd createAdvancingFront()
    {
        let triangle = .newTriangle(.points[0], nnPoint(.head), nnPoint(.tail))

        triangle.idx = .triangles.count
        .triangles.add(triangle)

        .afHead   = .newNode()
        .afMiddle = .newNode()
        .afTail   = .newNode()

        .front.head       = .afHead
        .front.tail       = .afTail
        .front.searchNode = nnNode(.afHead)

        .afHead.point    = triangle.points[1]
        .afHead.triangle = triangle
        .afHead.next     = .afMiddle
        .afHead.value    = .afHead.point.x

        .afMiddle.point    = triangle.points[0]
        .afMiddle.triangle = triangle
        .afMiddle.next     = .afTail
        .afMiddle.prev     = .afHead
        .afMiddle.value    = .afMiddle.point.x

        .afTail.point    = triangle.points[2]
        .afTail.triangle = triangle
        .afTail.prev     = .afMiddle
        .afTail.value    = .afTail.point.x
    }
}

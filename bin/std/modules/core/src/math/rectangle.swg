#global public
#global namespace Math

// Stores an axis-aligned rectangle as its top-left corner and its size.
//
// Y grows downward: `y` is the top edge and [[Core.Math.Rectangle.bottom]] is `y + height`. A
// rectangle is normalized when neither dimension is negative, which most operations assume;
// [[Core.Math.Rectangle.normalize]] restores it.
#[Swag.Operators(opEquals, opCompare), Serialization.Final]
struct Rectangle
{
    public
    {
        x:      f32     // Left edge
        y:      f32     // Top edge
        width:  f32     // Horizontal size
        height: f32     // Vertical size
    }
}

impl Rectangle
{
    const Zero = Rectangle{0, 0, 0, 0}     // Rectangle with all coordinates set to zero

    // Returns this rectangle with its position and size multiplied by `value`.
    //
    // This scales the rectangle about the origin, like [[Core.Math.Rectangle.scaledFromOrigin]].
    mtd(op: Swag.Operator) const opBinary(value: f32)->Rectangle
        where op == .Mul
    {
        return {.x * value, .y * value, .width * value, .height * value}
    }

    // Sets this rectangle to the one spanned by two opposite corners.
    //
    // The corners may come in any order: the result is always normalized.
    mtd set(topLeft, bottomRight: Math.Point)
    {
        .x      = Math.min(topLeft.x, bottomRight.x)
        .y      = Math.min(topLeft.y, bottomRight.y)
        .width  = Math.abs(bottomRight.x - topLeft.x)
        .height = Math.abs(bottomRight.y - topLeft.y)
    }

    // Returns the horizontal coordinate of the center.
    #[Swag.Inline]
    mtd const horzCenter()->f32 => .x + (.width * 0.5)

    // Returns the vertical coordinate of the center.
    #[Swag.Inline]
    mtd const vertCenter()->f32 => .y + (.height * 0.5)

    // Returns the center point.
    mtd const center()->Point => Point{.horzCenter(), .vertCenter()}

    // Returns the coordinate of the right edge, `x + width`.
    #[Swag.Inline]
    mtd const right()->f32 => .x + .width

    // Moves the right edge to `value` by changing the width, keeping the left edge in place.
    #[Swag.Inline]
    mtd setRight(value: f32)
    {
        .width = value - .x
    }

    // Returns the coordinate of the bottom edge, `y + height`.
    #[Swag.Inline]
    mtd const bottom()->f32 => .y + .height

    // Moves the bottom edge to `value` by changing the height, keeping the top edge in place.
    #[Swag.Inline]
    mtd setBottom(value: f32)
    {
        .height = value - .y
    }

    // Moves the left edge right by `value`, keeping the right edge in place.
    //
    // A positive `value` shrinks the rectangle and a negative one grows it.
    mtd moveLeft(value: f32)
    {
        .x     += value
        .width -= value
    }

    // Moves the right edge right by `value`, keeping the left edge in place.
    //
    // A positive `value` grows the rectangle and a negative one shrinks it.
    mtd moveRight(value: f32)
    {
        .width += value
    }

    // Moves the top edge down by `value`, keeping the bottom edge in place.
    //
    // A positive `value` shrinks the rectangle and a negative one grows it.
    mtd moveTop(value: f32)
    {
        .y      += value
        .height -= value
    }

    // Moves the bottom edge down by `value`, keeping the top edge in place.
    //
    // A positive `value` grows the rectangle and a negative one shrinks it.
    mtd moveBottom(value: f32)
    {
        .height += value
    }

    // Sets the position and the size to zero.
    mtd clear()
    {
        .x, .y, .width, .height = 0
    }

    // Returns whether the position and the size are all exactly zero.
    //
    // Use [[Core.Math.Rectangle.isZeroEpsilon]] for computed values.
    mtd const isZero()->bool => .x == 0 and .y == 0 and .width == 0 and .height == 0

    // Returns whether the width or the height is exactly zero.
    //
    // A rectangle with a negative dimension is not empty; normalize it first when that matters.
    mtd const isEmpty()->bool => .width == 0 or .height == 0

    // Returns whether neither the width nor the height is negative.
    mtd const isNormalized()->bool => .width >= 0 and .height >= 0

    // Moves the rectangle by `offsetXY` along both axes, keeping its size.
    mtd offset(offsetXY: f32)
    {
        .x, .y += offsetXY
    }

    // Moves the rectangle by `offsetX` horizontally and `offsetY` vertically, keeping its size.
    mtd offset(offsetX, offsetY: f32)
    {
        .x += offsetX
        .y += offsetY
    }

    // Moves the rectangle by the components of `offset`, keeping its size.
    mtd offset(offset: Math.Point)
    {
        .x += offset.x
        .y += offset.y
    }

    // Shrinks the rectangle by a separate padding on each side.
    //
    // The components of `padding` are the left, top, right, and bottom paddings, in that order.
    // Negative paddings grow the rectangle instead.
    mtd applyPadding(padding: Math.Vector4)
    {
        .x      += padding.x
        .y      += padding.y
        .width  -= (padding.x + padding.z)
        .height -= (padding.y + padding.w)
    }

    // Multiplies the width and the height by `value`, keeping the top-left corner in place.
    mtd scale(value: f32)
    {
        .width, .height *= value
    }

    // Multiplies the width by `x` and the height by `y`, keeping the top-left corner in place.
    mtd scale(x, y: f32)
    {
        .width  *= x
        .height *= y
    }

    // Returns this rectangle scaled by `value` about the origin.
    //
    // The position and the size are all multiplied by `value`, which is how a rectangle addresses
    // a proportionally scaled grid, such as a texture atlas built at another density.
    mtd const scaledFromOrigin(value: f32)->Rectangle => Rectangle{.x * value, .y * value, .width * value, .height * value}

    // Grows the rectangle by `value` on every side, keeping its center in place.
    //
    // A negative `value` shrinks it.
    mtd inflate(value: f32)
    {
        .x      -= value
        .y      -= value
        .width  += value * 2
        .height += value * 2
    }

    // Grows the rectangle by `x` on the left and right sides and by `y` on the top and bottom sides.
    //
    // The center stays in place, and negative amounts shrink the rectangle.
    mtd inflate(x, y: f32)
    {
        .x      -= x
        .y      -= y
        .width  += x * 2
        .height += y * 2
    }

    // Returns whether the position and the size are all closer to zero than `eps`.
    mtd const isZeroEpsilon(eps = ConstF32.Epsilon)->bool => isZeroEpsilon(.x, eps) and isZeroEpsilon(.y, eps) and isZeroEpsilon(.width, eps) and isZeroEpsilon(.height, eps)

    // Returns whether the width or the height is closer to zero than `eps`.
    mtd const isEmptyEpsilon(eps = ConstF32.Epsilon)->bool => isZeroEpsilon(.width, eps) or isZeroEpsilon(.height, eps)

    // Returns whether the position and the size are each closer than `eps` to those of `other`.
    mtd const isEqualEpsilon(other: Rectangle, eps = ConstF32.Epsilon)->bool
    {
        return isEqualEpsilon(.x, other.x, eps) and
               isEqualEpsilon(.y, other.y, eps) and
               isEqualEpsilon(.width, other.width, eps) and
               isEqualEpsilon(.height, other.height, eps)
    }

    // Rounds the position and the size to the nearest integer values in place.
    //
    // A value halfway between two integers rounds away from zero. The edges are not rounded
    // themselves, so the right edge can move by up to one unit.
    mtd round()
    {
        .x      = Math.round(.x)
        .y      = Math.round(.y)
        .width  = Math.round(.width)
        .height = Math.round(.height)
    }

    // Rounds the position and the size toward zero in place.
    mtd trunc()
    {
        .x      = Math.trunc(.x)
        .y      = Math.trunc(.y)
        .width  = Math.trunc(.width)
        .height = Math.trunc(.height)
    }

    // Rounds the position and the size up to integer values in place.
    mtd ceil()
    {
        .x      = Math.ceil(.x)
        .y      = Math.ceil(.y)
        .width  = Math.ceil(.width)
        .height = Math.ceil(.height)
    }

    // Returns whether the point (`x`, `y`) lies inside the rectangle.
    //
    // The left and top edges are inside and the right and bottom edges are outside, so
    // rectangles that tile a surface never both contain a point on their shared edge. An empty
    // rectangle contains no point.
    mtd const contains(x, y: f32)->bool => (x >= .x and x < .x + .width) and (y >= .y and y < .y + .height)

    // Returns whether `pt` lies inside the rectangle, with the edge rules of the coordinate form.
    mtd const contains(pt: Point)->bool => .contains(pt.x, pt.y)

    // Returns whether `rect` lies entirely inside this rectangle.
    //
    // Shared edges count as inside, so a rectangle contains itself.
    mtd const contains(rect: Rectangle)->bool => (rect.x >= .x and rect.right() <= .right()) and (rect.y >= .y and rect.bottom() <= .bottom())

    // Replaces this rectangle with its intersection with `other`.
    //
    // It becomes [[Core.Math.Rectangle.Zero]] when the two do not overlap.
    mtd intersect(other: Rectangle)
    {
        let current: Rectangle = me
        me[] = intersect(current, other)
    }

    // Returns the overlapping area of `a` and `b`.
    //
    // The result is [[Core.Math.Rectangle.Zero]] when the overlap has no area, which includes
    // rectangles that only share an edge.
    func intersect(a, b: Rectangle)->Rectangle
    {
        let x1 = max(a.x, b.x)
        let x2 = min(a.x + a.width, b.x + b.width)
        let y1 = max(a.y, b.y)
        let y2 = min(a.y + a.height, b.y + b.height)
        if x2 > x1 and y2 > y1 do
            return Rectangle{x1, y1, x2 - x1, y2 - y1}
        return Zero
    }

    // Returns whether this rectangle and `rect` overlap.
    //
    // Rectangles that only share an edge do not intersect.
    mtd const intersects(rect: Rectangle)->bool => (rect.x < .right()) and (.x < rect.right()) and (rect.y < .bottom()) and (.y < rect.bottom())

    // Replaces this rectangle with the smallest one containing both it and `other`.
    //
    // Like [[Core.Math.Rectangle.combined]], an empty rectangle still extends the result to its position.
    mtd combine(other: Rectangle)
    {
        let current: Rectangle = me
        me[] = combined(current, other)
    }

    // Returns the smallest rectangle containing both `a` and `b`.
    //
    // An empty rectangle is not ignored: its position still extends the result.
    func combined(a, b: Rectangle)->Rectangle
    {
        let x1 = min(a.x, b.x)
        let x2 = max(a.right(), b.right())
        let y1 = min(a.y, b.y)
        let y2 = max(a.bottom(), b.bottom())
        return Rectangle{x1, y1, x2 - x1, y2 - y1}
    }

    // Returns the area, `width * height`.
    //
    // It is negative when exactly one dimension is negative.
    #[Swag.Inline]
    mtd const area()->f32 => .width * .height

    // Returns the perimeter, `2 * (width + height)`.
    #[Swag.Inline]
    mtd const perimeter()->f32 => 2.0 * (.width + .height)

    // Returns the aspect ratio, `width / height`, or 0 when the height is zero.
    mtd const aspectRatio()->f32
    {
        if .height == 0 do
            return 0
        return .width / .height
    }

    // Makes the width and the height non-negative in place, covering the same area.
    //
    // A negative dimension moves the matching edge to the other side of the rectangle.
    mtd normalize()
    {
        if .width < 0
        {
            .x     += .width
            .width = -.width
        }

        if .height < 0
        {
            .y      += .height
            .height = -.height
        }
    }

    // Returns this rectangle with a non-negative width and height, covering the same area.
    mtd const normalized()->Rectangle
    {
        var result: retval = me
        result.normalize()
        return result
    }

    // Returns the top-left corner.
    #[Swag.Inline]
    mtd const topLeft()->Point => Point{.x, .y}

    // Returns the top-right corner.
    #[Swag.Inline]
    mtd const topRight()->Point => Point{.x + .width, .y}

    // Returns the bottom-left corner.
    #[Swag.Inline]
    mtd const bottomLeft()->Point => Point{.x, .y + .height}

    // Returns the bottom-right corner.
    #[Swag.Inline]
    mtd const bottomRight()->Point => Point{.x + .width, .y + .height}

    // Returns the width and the height as a point.
    #[Swag.Inline]
    mtd const size()->Point => Point{.width, .height}

    // Sets the width and the height from `newSize`, keeping the top-left corner in place.
    mtd setSize(newSize: Point)
    {
        .width  = newSize.x
        .height = newSize.y
    }

    // Returns the point of the rectangle closest to `pt`, edges included.
    //
    // A point inside is returned unchanged. The rectangle must be normalized.
    mtd const clampPoint(pt: Point)->Point => Point{Math.clamp(pt.x, .x, .x + .width), Math.clamp(pt.y, .y, .y + .height)}

    // Returns the distance from `pt` to the rectangle, or 0 when the point is inside or on an edge.
    mtd const distanceToPoint(pt: Point)->f32
    {
        let clamped = .clampPoint(pt)
        let dx      = pt.x - clamped.x
        let dy      = pt.y - clamped.y
        return Math.sqrt(dx * dx + dy * dy)
    }

    // Scales this rectangle to the largest size that fits in `bounds`, keeping its aspect ratio, then centers it there.
    //
    // A rectangle with a zero width or height has no aspect ratio and is left unchanged.
    mtd fitWithin(bounds: Rectangle)
    {
        if .width == 0 or .height == 0 do
            return

        let scaleX = bounds.width / .width
        let scaleY = bounds.height / .height
        let scale  = Math.min(scaleX, scaleY)

        .width  *= scale
        .height *= scale
        .x      = bounds.x + (bounds.width - .width) * 0.5
        .y      = bounds.y + (bounds.height - .height) * 0.5
    }

    // Returns `rect` scaled to the largest size that fits in `bounds`, keeping its aspect ratio, and centered there.
    //
    // This is the value form of [[Core.Math.Rectangle.fitWithin]].
    func fittedWithin(rect: Rectangle, bounds: Rectangle)->Rectangle
    {
        var result = rect
        result.fitWithin(bounds)
        return result
    }

    // Grows the rectangle just enough to contain `pt`.
    mtd expandToInclude(pt: Point)
    {
        let right     = .x + .width
        let bottom    = .y + .height
        let newLeft   = Math.min(.x, pt.x)
        let newTop    = Math.min(.y, pt.y)
        let newRight  = Math.max(right, pt.x)
        let newBottom = Math.max(bottom, pt.y)

        .x      = newLeft
        .y      = newTop
        .width  = newRight - newLeft
        .height = newBottom - newTop
    }

    // Grows the rectangle just enough to contain `other`.
    mtd expandToInclude(other: Rectangle)
    {
        .expandToInclude(other.topLeft())
        .expandToInclude(other.bottomRight())
    }
}

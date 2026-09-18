#global namespace Math
#global public

// Stores a 2D affine transform as a 3 by 2 matrix applied to row vectors.
//
// A point (x, y) maps to (x * m11 + y * m21 + tx, x * m12 + y * m22 + ty): the first two rows
// rotate, scale, and skew, and the last row translates.
struct Transform2
{
    public
    {
        m11, m12: f32     // First row of the linear part, where the X axis goes
        m21, m22: f32     // Second row of the linear part, where the Y axis goes
        m31, m32: f32     // Translation, also reachable as tx and ty

        #[Swag.Offset("m11")]
        m: [2, 2] f32     // Linear part as an array indexed by row, then column
        #[Swag.Offset("m31")]
        tx: f32     // Translation along the X axis, stored in m31
        #[Swag.Offset("m32")]
        ty: f32     // Translation along the Y axis, stored in m32
    }
}

impl Transform2
{
    const Identity = Transform2{1, 0, 0, 1, 0, 0}     // Identity transform, which leaves every point in place

    // Resets this transform to the identity.
    mtd setIdentity()
    {
        me[] = Identity
    }

    // Returns whether this transform is exactly the identity.
    mtd const isIdentity()->bool => .m11 == 1 and .m12 == 0 and .m21 == 0 and .m22 == 1 and .tx == 0 and .ty == 0

    // Returns whether the linear part is exactly the identity, so the transform only translates.
    //
    // An axis-aligned shape stays axis aligned and pixel-snapped under such a transform.
    mtd const isTranslationOnly()->bool => .m11 == 1 and .m12 == 0 and .m21 == 0 and .m22 == 1

    // Creates a rotation by `angle` radians about the point (`centerX`, `centerY`).
    //
    // A positive angle turns the X axis toward the Y axis.
    func createRotation(angle: f32, centerX, centerY: f32)->Transform2
    {
        let s  = Math.sin(angle)
        let c  = Math.cos(angle)
        let c1 = 1.0 - c

        with var result: retval
        {
            .tx  = (centerX * c1) + (centerY * s)
            .ty  = (centerY * c1) - (centerX * s)
            .m11 = c
            .m12 = s
            .m21 = -s
            .m22 = c
        }

        return result
    }

    // Creates a scale by `scaleX` and `scaleY` about the point (`centerX`, `centerY`).
    //
    // The center stays in place, and a negative factor mirrors across it.
    func createScale(scaleX, scaleY: f32, centerX, centerY: f32)->Transform2
    {
        with var result: retval
        {
            .m11 = scaleX
            .m12 = 0
            .m21 = 0
            .m22 = scaleY
            .tx  = centerX - scaleX * centerX
            .ty  = centerY - scaleY * centerY
        }

        return result
    }

    // Creates a translation by `x` along the X axis and `y` along the Y axis.
    func createTranslation(x, y: f32)->Transform2
    {
        with var result: retval
        {
            .m11 = 1
            .m12 = 0
            .m21 = 0
            .m22 = 1
            .tx  = x
            .ty  = y
        }

        return result
    }

    // Replaces the translation with `translation`, keeping the linear part.
    mtd setTranslation(translation: Vector2)
    {
        .tx = translation.x
        .ty = translation.y
    }

    // Returns the translation components.
    mtd const translation()->Vector2 => Vector2{.tx, .ty}

    // Returns `point` mapped through this transform.
    mtd const transformPoint(point: Vector2)->Vector2
    {
        let rx = point.x * .m11 + point.y * .m21 + .tx
        let ry = point.x * .m12 + point.y * .m22 + .ty
        return Vector2{rx, ry}
    }

    // Returns `vector` mapped through the linear part of this transform, without the translation.
    //
    // Use it for directions and offsets, which a translation must not move, and
    // [[Core.Math.Transform2.transformPoint]] for positions.
    mtd const transformVector(vector: Vector2)->Vector2 => Vector2{vector.x * .m11 + vector.y * .m21, vector.x * .m12 + vector.y * .m22}

    // Returns how much the transform stretches each axis: the lengths of the transformed unit X
    // and unit Y vectors.
    //
    // A rotation or a reflection leaves both at 1; the translation plays no part.
    mtd const axisScale()->Vector2 => {Math.sqrt(.m11 * .m11 + .m12 * .m12), Math.sqrt(.m21 * .m21 + .m22 * .m22)}

    // Returns the axis-aligned rectangle enclosing `rect` once transformed.
    //
    // The four corners are mapped, because a rotated or skewed rectangle is no longer
    // described by an origin and an extent. The result is the smallest rectangle holding the
    // transformed shape, which is what a caller rejecting work against a viewport needs.
    //
    // ```swag
    // if not viewport.intersects(transform.transformBounds(item.bounds)) do
    //     continue
    // ```
    mtd const transformBounds(rect: Rectangle)->Rectangle
    {
        let p0  = .transformPoint({rect.x, rect.y})
        let p1  = .transformPoint({rect.right(), rect.y})
        let p2  = .transformPoint({rect.x, rect.bottom()})
        let p3  = .transformPoint({rect.right(), rect.bottom()})
        let min = Vector2.min(Vector2.min(p0, p1), Vector2.min(p2, p3))
        let max = Vector2.max(Vector2.max(p0, p1), Vector2.max(p2, p3))
        return Rectangle{min.x, min.y, max.x - min.x, max.y - min.y}
    }

    // Returns the transform that maps every transformed point back to where it came from.
    //
    // A singular transform — one that flattens the plane onto a line or a point — has no
    // inverse. The identity is returned for it rather than a matrix of infinities, so a caller
    // mapping through the result still gets finite coordinates. A transform counts as singular
    // when the determinant of its linear part is zero or too small for its reciprocal to be
    // finite; a tiny but valid scale still inverts.
    //
    // ```swag
    // let local = placement.inverse().transformPoint(pagePoint)
    // ```
    mtd const inverse()->Transform2
    {
        let det   = .m11 * .m22 - .m12 * .m21
        let scale = 1.0 / det
        if det == 0 or not isFinite(scale) do
            return Identity

        var result: retval
        result.m11 = .m22 * scale
        result.m12 = -.m12 * scale
        result.m21 = -.m21 * scale
        result.m22 = .m11 * scale
        result.tx  = -(.tx * result.m11 + .ty * result.m21)
        result.ty  = -(.tx * result.m12 + .ty * result.m22)
        return result
    }

    // Composes `other` after this transform, in place.
    //
    // The result applies this transform first and `other` second: it maps a point `p` to
    // `other.transformPoint(transformPoint(p))`. `other` may be this transform itself.
    mtd multiply(other: Transform2)
    {
        // `other` is read through its address and can alias `me`: every product is computed
        // before the first field is written.
        let m11 = .m11 * other.m11 + .m12 * other.m21
        let m12 = .m11 * other.m12 + .m12 * other.m22
        let m21 = .m21 * other.m11 + .m22 * other.m21
        let m22 = .m21 * other.m12 + .m22 * other.m22
        let tx  = .tx * other.m11 + .ty * other.m21 + other.tx
        let ty  = .tx * other.m12 + .ty * other.m22 + other.ty
        me[] = {m11, m12, m21, m22, tx, ty}
    }
}

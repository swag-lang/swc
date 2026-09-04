#global namespace Math
#global public

// 2D transformation matrix structure
struct Transform2
{
    public
    {
        m11, m12: f32     // First row of the 2D transformation matrix
        m21, m22: f32     // Second row of the 2D transformation matrix
        m31, m32: f32     // Translation components of the transformation

        #[Swag.Offset("m11")]
        m: [2, 2] f32     // 2x2 matrix view for rotation/scale components
        #[Swag.Offset("m31")]
        tx: f32     // Translation component along X-axis
        #[Swag.Offset("m32")]
        ty: f32     // Translation component along Y-axis
    }
}

impl Transform2
{
    const Identity = Transform2{1, 0, 0, 1, 0, 0}     // Identity transform (no rotation, scale 1, no translation)

    // Set transform to identity
    mtd setIdentity()
    {
        me[] = Identity
    }

    // Checks if the transform is the identity matrix
    mtd const isIdentity()->bool
    {
        return .m11 == 1 and .m12 == 0 and .m21 == 0 and .m22 == 1 and .tx == 0 and .ty == 0
    }

    // Checks if the linear part is the identity, i.e. the transform is a pure
    // translation (no rotation, no scale). An axis-aligned shape stays axis
    // aligned and pixel-snapped under such a transform.
    mtd const isTranslationOnly()->bool
    {
        return .m11 == 1 and .m12 == 0 and .m21 == 0 and .m22 == 1
    }

    // Creates a rotation matrix, with a given center of rotation
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

    // Creates a scale matrix, with a given center
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

    // Creates a translation matrix
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

    // Sets the translation components directly
    mtd setTranslation(translation: Vector2)
    {
        .tx = translation.x
        .ty = translation.y
    }

    // Returns the translation components.
    mtd const translation()->Vector2
    {
        return Vector2{.tx, .ty}
    }

    // Applies the transform to a 2D point
    mtd const transformPoint(point: Vector2)->Vector2
    {
        let rx = point.x * .m11 + point.y * .m21 + .tx
        let ry = point.x * .m12 + point.y * .m22 + .ty
        return Vector2{rx, ry}
    }

    // Returns the axis-aligned rectangle enclosing `rect` once transformed.
    //
    // The four corners are mapped, because a rotated or skewed rectangle is no longer
    // described by an origin and an extent. The result is the smallest rectangle holding the
    // transformed shape, which is what a caller rejecting work against a viewport needs.
    //
    // ```swag
    // if !viewport.intersects(transform.transformBounds(item.bounds)) do
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
    // mapping through the result still gets finite coordinates.
    //
    // ```swag
    // let local = placement.inverse().transformPoint(pagePoint)
    // ```
    mtd const inverse()->Transform2
    {
        let det = .m11 * .m22 - .m12 * .m21
        if isZeroEpsilon(det) do
            return Identity

        let scale = 1.0 / det
        var result: retval
        result.m11 = .m22 * scale
        result.m12 = -.m12 * scale
        result.m21 = -.m21 * scale
        result.m22 = .m11 * scale
        result.tx  = -(.tx * result.m11 + .ty * result.m21)
        result.ty  = -(.tx * result.m12 + .ty * result.m22)
        return result
    }

    // Multiplies the current transform by another transformation matrix
    mtd multiply(matrix2: Transform2)
    {
        let sm11 = .m11
        .m11 = sm11 * matrix2.m11 + .m12 * matrix2.m21
        .m12 = sm11 * matrix2.m12 + .m12 * matrix2.m22

        let sm21 = .m21
        .m21 = sm21 * matrix2.m11 + .m22 * matrix2.m21
        .m22 = sm21 * matrix2.m12 + .m22 * matrix2.m22

        let stx = .tx
        .tx = stx * matrix2.m11 + .ty * matrix2.m21 + matrix2.tx
        .ty = stx * matrix2.m12 + .ty * matrix2.m22 + matrix2.ty
    }
}

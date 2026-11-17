#global namespace Math
#global public

// Stores a 3D position, rotation, and scale.
//
// Points are scaled, rotated, then translated. Normals use inverse scale and rotation and require
// every scale component to be nonzero.
#[Serialization.Final]
struct Transform3
{
    public position: Vector3     // Translation in world space.
    public rotation: Quaternion  // Orientation as a unit quaternion.
    public scale: Vector3         // Per-axis local scale.
}

impl Transform3
{
    const Identity = Transform3{Vector3.Zero, Quaternion.Identity, Vector3.One}     // Leaves points unchanged.

    // Transforms a point by scale, rotation, and translation.
    mtd const transformPoint(point: Vector3)->Vector3 => .rotation.rotate(point * .scale) + .position

    // Transforms a direction by scale and rotation, without applying translation.
    mtd const transformDirection(direction: Vector3)->Vector3 => .rotation.rotate(direction * .scale)

    // Transforms a normal by inverse scale and rotation; each scale component must be nonzero.
    mtd const transformNormal(normal: Vector3)->Vector3
    {
        Swag.assert(.scale.x != 0 and .scale.y != 0 and .scale.z != 0)
        return .rotation.rotate(normal / .scale)
    }

    // Maps a world-space point back through translation, rotation, and scale.
    mtd const inverseTransformPoint(point: Vector3)->Vector3
    {
        Swag.assert(.scale.x != 0 and .scale.y != 0 and .scale.z != 0)
        return .rotation.inverse().rotate(point - .position) / .scale
    }

    // Returns the equivalent row-major matrix for row-vector transforms.
    mtd const toMatrix4x4()->Matrix4x4 => Matrix4x4.createTRS(.position, .rotation, .scale)
}

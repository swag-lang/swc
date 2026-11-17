#global public

using Core

// Bounds the bytes and geometry accepted by a scene decoder.
public struct Limits
{
    public
    {
        // Maximum encoded bytes read by `load` or accepted by `decode`.
        maxInputBytes: u64 = 32 * 1024 * 1024

        // Maximum vertices stored across all meshes.
        maxVertices: u64 = 1_000_000

        // Maximum triangles stored across all meshes.
        maxTriangles: u64 = 2_000_000

        // Maximum nodes and materials stored in the scene.
        maxNodes: u32 = 65_536
        maxMaterials: u32 = 65_536
    }
}

public impl Limits
{
    // Reports whether every configured resource limit is nonzero.
    mtd const isValid()->bool => .maxInputBytes != 0 and .maxVertices != 0 and .maxTriangles != 0 and .maxNodes != 0 and .maxMaterials != 0
}

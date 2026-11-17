#global public

using Core, Core.Errors

// Axis-aligned bounds in the coordinate system and units of the source scene.
public struct Bounds
{
    public
    {
        // Lower corner of the box; meaningful when `isEmpty` is false.
        min: Math.Vector3

        // Upper corner of the box; meaningful when `isEmpty` is false.
        max: Math.Vector3

        // Whether no point has been included yet.
        isEmpty: bool = true
    }
}

public impl Bounds
{
    // Includes a finite point in this box.
    //
    // A non-finite component fails with [[Core.Errors.InvalidFormatError]] without changing the box.
    mtd include(point: Math.Vector3) fail
    {
        if not Math.isFinite(point.x) or not Math.isFinite(point.y) or not Math.isFinite(point.z) do
            fail InvalidFormatError{"bound point has a non-finite coordinate"}
        if .isEmpty
        {
            .min     = point
            .max     = point
            .isEmpty = false
            return
        }

        .min.x = Math.min(.min.x, point.x)
        .min.y = Math.min(.min.y, point.y)
        .min.z = Math.min(.min.z, point.z)
        .max.x = Math.max(.max.x, point.x)
        .max.y = Math.max(.max.y, point.y)
        .max.z = Math.max(.max.z, point.z)
    }
}

// One decoded mesh vertex with optional source normal and texture coordinates.
public struct Vertex
{
    public
    {
        // Position in the source coordinate system and units.
        position: Math.Vector3

        // Normal as stored by the source, when present; it is not normalized by the decoder.
        normal: Math.Vector3

        // Whether the source supplied a normal for this vertex.
        hasNormal: bool

        // Texture coordinate when the source provides one.
        texCoord: Math.Vector2

        // Whether the source supplied texture coordinates for this vertex.
        hasTexCoord: bool
    }
}

// One triangle indexing three vertices in its owning mesh.
public struct Triangle
{
    public
    {
        // Indices of the three vertices in the containing mesh.
        a, b, c: u32

        // Material index in the containing scene, or -1 when the source assigns none.
        materialIndex: s32 = -1
    }
}

// A named triangle mesh with its local bounds.
public struct Mesh
{
    public
    {
        // Display name retained from the source, or a generic name when none exists.
        name: String

        // Vertices referenced by this mesh's triangles.
        vertices: Array'Vertex

        // Triangle indices into `vertices`.
        triangles: Array'Triangle

        // Bounds of the vertices referenced by this mesh.
        bounds: Bounds
    }
}

// A named material record referenced by mesh triangles.
public struct Material
{
    public
    {
        // Source material name, or `Default` when no material is assigned.
        name: String

        // RGBA base color in linear components; defaults to opaque white.
        baseColor: Math.Vector4 = Math.Vector4{1, 1, 1, 1}

        // Relative source path for a diffuse texture, when a codec records one.
        diffuseTexture: String
    }
}

// One scene graph node that instances a mesh with a local transform.
public struct Node
{
    public
    {
        // Source node name, or the scene's file name for its synthetic root.
        name: String

        // Parent node index, or -1 for a root node.
        parentIndex: s32 = -1

        // Instanced mesh index, or -1 when the node has no mesh.
        meshIndex: s32 = -1

        // Transform from this node's local coordinates to its parent's coordinates.
        localTransform: Math.Matrix4x4
    }
}

public impl Node
{
    // Creates a root node with an identity local transform.
    func create(name: string = "")->Node
    {
        var result: #returntype
        result.name = String.from(name)
        result.localTransform = Math.Matrix4x4.createIdentity()
        return result
    }
}

// An owned, renderer-independent scene containing geometry and its source structure.
public struct Scene
{
    public
    {
        // File name or declared scene name.
        name: String

        // Nodes in parent-before-child order. A mesh can be instanced by multiple nodes.
        nodes: Array'Node

        // Meshes indexed by [[Scene3d.Node.meshIndex]].
        meshes: Array'Mesh

        // Materials indexed by [[Scene3d.Triangle.materialIndex]].
        materials: Array'Material

        // Axis-aligned bounds of decoded mesh positions in source coordinates.
        bounds: Bounds
    }
}

public impl Scene
{
    // Returns the formats supported by `load` and `decode` as an owned snapshot.
    func decodableFormats()->Array'SceneFormat => sceneFormats()

    // Reports whether a built-in scene decoder claims `fileName` by extension alone.
    func canLoad(fileName: string)->bool => sceneCodec(fileName) != .Unknown

    // Creates an empty scene with no nodes, meshes, or materials.
    func create(name: string = "")->Scene
    {
        var result: #returntype
        result.name = String.from(name)
        return result
    }
}

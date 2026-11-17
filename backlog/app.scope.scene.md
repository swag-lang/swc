# Swag Scope 3D scene viewer backlog

This domain covers local, read-only inspection of 3D models and scenes in Swag Scope. The viewer
must follow the common viewer contract in [app.scope.viewers.md](app.scope.viewers.md), the Swag
Scope presentation in [design/README.md](design/README.md#swag-scope), and the single-executable,
Swag-implemented product gate described by the [viewer audit](../bin/apps/modules/swagscope/FEATURE_AUDIT.md).

### app.scope.scene.001 — The 3D scene reader lacks common scene formats and inspection

- Evidence: the `scene3d` standard module and Swag Scope viewer currently read static OBJ meshes
  and ASCII/binary STL. [Blender](https://docs.blender.org/manual/en/latest/files/import_export.html)
  and [MeshLab](https://www.meshlab.net/) also inspect material libraries, textures, scene
  hierarchy, transforms, and glTF 2.0 scenes, while this reader displays one triangle mesh without
  selection, material visualization, or multiple-node transforms.
- Next: replace or constrain fan triangulation so concave OBJ polygons cannot be silently
  misrendered, with parser fixtures that cover convex and concave faces. Then add glTF 2.0
  (`.gltf`/`.glb`) to `std/scene3d` with bounded buffers and accessors, preserve nodes and transforms
  through the shared scene model and display them in Scope. Resolve OBJ `mtllib` and texture
  sidecars only beneath an explicitly chosen scene directory; reject traversal, absolute paths, URLs
  and other external schemes, and report missing resources.
- Done when: the built-in viewer opens and reliably identifies OBJ/MTL, STL (ASCII and binary),
  and glTF 2.0/GLB scenes; fits and frames valid geometry; supports orbit, pan, zoom, reset and
  frame-all; exposes a selectable scene/node and mesh hierarchy with names, transforms, bounds,
  vertex/triangle counts, material assignments and texture status; triangulates or clearly rejects
  concave faces; reports malformed, missing,
  unsupported and resource-limited content visibly; handles large or hostile inputs within stated
  memory, work and texture limits, including hostile sidecar paths; and has focused parser,
  lifecycle, theme and golden coverage under the common viewer test contract. The display follows
  the Scope Silence charter in Encre and
  Papier, preserves geometry without distortion, and uses existing selection/focus roles rather
  than introducing a viewer-specific palette.
- Later parity: add PLY and 3MF after the initial formats, followed by FBX and USD only when their
  format complexity, licensing and self-contained implementation costs are understood; consider
  Collada (`.dae`) as a lower-priority legacy interchange format. Extend the
  scene model to textured PBR materials, cameras, lights and multiple scenes; add perspective and
  orthographic views, axes/grid, wireframe and material/normal visualization, mesh statistics and
  measurements, animation timeline and keyframe scrubbing, including glTF skinning and morph targets
  or explicit diagnostics for them, and camera/scene switching. Keep unsupported extensions and
  animation channels named in the information sheet rather than silently
  flattening them. Compare opening, first-frame latency and memory against the named reference on
  licensed real-world fixtures, and keep opening local files offline.
- Related: app.scope.viewers.009, app.scope.viewers.014

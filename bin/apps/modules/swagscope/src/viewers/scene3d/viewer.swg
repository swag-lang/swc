#global internal
#global namespace Viewers.Scene

using Core, Pixel, Gui

// Loads a scene through the shared format-neutral decoder and validates the camera range.
private func loadScene(fileName: string)->Scene3d.Scene fail
{
    let scene = try Scene3d.load(fileName)
    discard try cameraFrame(scene.bounds)
    return scene
}

private struct CameraFrame
{
    center: Math.Vector3
    radius: f32
}

// Computes camera dimensions in f64 so finite f32 coordinates cannot overflow while framing.
private func cameraFrame(bounds: Scene3d.Bounds)->CameraFrame fail
{
    var result: #returntype
    if bounds.isEmpty do
        return result

    let centerX = (cast(f64, bounds.min.x) + cast(f64, bounds.max.x)) * 0.5
    let centerY = (cast(f64, bounds.min.y) + cast(f64, bounds.max.y)) * 0.5
    let centerZ = (cast(f64, bounds.min.z) + cast(f64, bounds.max.z)) * 0.5
    let halfX   = (cast(f64, bounds.max.x) - cast(f64, bounds.min.x)) * 0.5
    let halfY   = (cast(f64, bounds.max.y) - cast(f64, bounds.min.y)) * 0.5
    let halfZ   = (cast(f64, bounds.max.z) - cast(f64, bounds.min.z)) * 0.5
    let radius  = Math.sqrt(halfX * halfX + halfY * halfY + halfZ * halfZ)
    if not Math.isFinite(radius) or radius > cast(f64, Swag.F32.Max) / 5 do
        fail Errors.InvalidFormatError{texts().err_RangeUnsupported}

    result.center = Math.Vector3{cast(f32, centerX), cast(f32, centerY), cast(f32, centerZ)}
    result.radius = Math.max(cast(f32, radius), 0.001)
    return result
}

// Uses shared decoders for extensionless text meshes; binary STL needs its `.stl` extension because
// the host deliberately supplies only a 4 KiB prefix, not the complete length-bearing buffer.
private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    return Scene3d.canDecode(content.fileName, content.head)
}

private struct ProjectedTriangle
{
    points: [3] Math.Vector2
    depth:  f32
}

// Describes the scene viewer to the host; its format list comes from the shared codec module.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "scene3d"
        .staticName   = "3D Scene"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Scene3d)
        .create       = &createViewer
        .probe        = &pluginProbe
        .smokeFixture = "viewer.obj"
    }

    for format in Scene3d.Scene.decodableFormats() do
        result.addSelectors(format.extensions)
    return result
}

// Owns one loaded scene and the camera gesture state for its session.
struct Panel
{
    using wnd: Wnd

    scene:         Scene3d.Scene
    load:          Viewer.BackgroundLoad'Scene3d.Scene
    services:      Viewer.HostServices
    failureReason: String
    center:        Math.Vector3
    yaw:           f32 = 0.65
    pitch:         f32 = 0.45
    zoomPercent:   u32 = 100
    radius:        f32 = 1
    dragging:      bool
    panning:       bool
    pan:           Math.Vector2
    projected:     Array'ProjectedTriangle

    late
    {
        zoomLabel: *IconButton
    }
}

private impl Panel
{
    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.scene3d")
        {
            .backgroundStyle = .View
            .services        = host.services()
        }

        with result.zoomLabel = Viewer.createZoomButton(host.createInfoGroup(Viewer.ZoomSlotWidth), "scope.scene3d.zoom", texts().ui_ZoomMenu)
        {
            .sigPressed += func|view = result|(_) { view.showZoomMenu() }
        }

        result.zoomLabel.setText(Viewer.zoomText(result.zoomPercent))
        result.load.start(host.fileName(), &loadScene, result)
        return result
    }

    mtd publish(scene: *Scene3d.Scene)
    {
        .scene = #move scene[]
        if not .scene.bounds.isEmpty
        {
            let frame = expect cameraFrame(.scene.bounds)
            .center = frame.center
            .radius = frame.radius
        }

        .services.showDetails(me, .detailsText())
        .invalidate()
    }

    mtd triangleCount()->u64
    {
        var result = 0'u64
        for mesh in .scene.meshes do
            result += mesh.triangles.count
        return result
    }

    mtd vertexCount()->u64
    {
        var result = 0'u64
        for mesh in .scene.meshes do
            result += mesh.vertices.count
        return result
    }

    mtd detailsText()->String => Format.toString(texts().ui_Details,
                                                 .scene.meshes.count,
                                                 .triangleCount(),
                                                 .vertexCount())

    mtd resetCamera()
    {
        .yaw         = 0.65
        .pitch       = 0.45
        .zoomPercent = 100
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
        .pan = {}
        .invalidate()
    }

    internal mtd setZoomPercent(value: u32)
    {
        .zoomPercent = Viewer.clampZoom(value)
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
        .invalidate()
    }

    mtd zoomFactor()->f32 => cast(f32, .zoomPercent) / 100

    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoomPercent(percent)
    }

    mtd rotate(horizontal, vertical: f32)
    {
        .yaw   += horizontal
        .pitch = Math.max(Math.min(.pitch + vertical, 1.5), -1.5)
        .invalidate()
    }

    mtd panBy(horizontal, vertical: f32)
    {
        .pan.x += horizontal
        .pan.y += vertical
        .invalidate()
    }

    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let unavailable = .scene.meshes.isEmpty()
        entries.add(texts().ui_FrameAll, .FitView, func|view = me|() { view.resetCamera() }, shortcut: Input.formatKeyShortcut(.None, .F), disabled: unavailable)
        entries.addZoom(.In, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.In, me.zoomPercent)|() { view.setZoomPercent(percent) })
        entries.addZoom(.Out, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Out, me.zoomPercent)|() { view.setZoomPercent(percent) })
        entries.addZoom(.Reset, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Reset, me.zoomPercent)|() { view.setZoomPercent(percent) })
        entries.add(appStrings().cmd_ZoomMenu, .ZoomIn, func|view = me|() { view.showZoomMenu() })
        entries.add(texts().ui_OrbitLeft, .ChevronLeft, func|view = me|() { view.rotate(-0.15, 0) }, disabled: unavailable)
        entries.add(texts().ui_OrbitRight, .ChevronRight, func|view = me|() { view.rotate(0.15, 0) }, disabled: unavailable)
        entries.add(texts().ui_OrbitUp, .ChevronUp, func|view = me|() { view.rotate(0, -0.15) }, disabled: unavailable)
        entries.add(texts().ui_OrbitDown, .ChevronDown, func|view = me|() { view.rotate(0, 0.15) }, disabled: unavailable)
        entries.add(texts().ui_PanLeft, .ChevronLeft, func|view = me|() { view.panBy(-24, 0) }, disabled: unavailable)
        entries.add(texts().ui_PanRight, .ChevronRight, func|view = me|() { view.panBy(24, 0) }, disabled: unavailable)
        entries.add(texts().ui_PanUp, .ChevronUp, func|view = me|() { view.panBy(0, -24) }, disabled: unavailable)
        entries.add(texts().ui_PanDown, .ChevronDown, func|view = me|() { view.panBy(0, 24) }, disabled: unavailable)
    }

    mtd retire()->bool => .load.retire()
}

private impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .zoomLabel.toolTip = texts().ui_ZoomMenu
            .services.showDetails(me, .detailsText())
            .services.informationChanged(me)
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        var scene: Scene3d.Scene
        .failureReason = .load.finish(&scene)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .publish(&scene)
        .services.loadingChanged(me)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Wheel and (evt.modifiers == .None or evt.modifiers == .Control)
        {
            .setZoomPercent(evt.delta.y > 0 ? Viewer.zoomIn(.zoomPercent) : Viewer.zoomOut(.zoomPercent))
            return
        }

        if evt.kind == .Pressed and evt.button == .Left
        {
            .dragging = true
            return
        }

        if evt.kind == .Released and evt.button == .Left
        {
            .dragging = false
            return
        }

        if evt.kind == .Pressed and evt.button == .Right
        {
            .panning = true
            return
        }

        if evt.kind == .Released and evt.button == .Right
        {
            .panning = false
            return
        }

        if evt.kind == .Move and .dragging
        {
            .rotate(cast(f32, evt.delta.x) * 0.01, cast(f32, evt.delta.y) * 0.01)
            return
        }

        if evt.kind == .Move and .panning
        {
            .panBy(cast(f32, evt.delta.x), cast(f32, evt.delta.y))
            return
        }

        evt.accepted = false
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if evt.key == .F and evt.modifiers == .None
        {
            .resetCamera()
            return
        }

        if Viewer.isZoomKey(evt)
        {
            .setZoomPercent(Viewer.zoomAfterKey(evt, .zoomPercent))
            return
        }

        if evt.modifiers == .Alt or evt.modifiers == .Shift
        {
            let panMode = evt.modifiers == .Shift
            switch evt.key
            {
            case .Left:
                if panMode do
                    .panBy(-24, 0) else do
                        .rotate(-0.12, 0)

            case .Right:
                if panMode do
                    .panBy(24, 0) else do
                        .rotate(0.12, 0)

            case .Up:
                if panMode do
                    .panBy(0, -24) else do
                        .rotate(0, -0.12)

            case .Down:
                if panMode do
                    .panBy(0, 24) else do
                        .rotate(0, 0.12)

            default:
                evt.accepted = false
            }

            return
        }

        evt.accepted = false
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .scene.bounds.isEmpty do
            return

        let painter  = evt.paintContext.painter
        let colors   = .themeColors()
        let client   = .clientRect()
        let metrics  = .themeMetrics()
        let focal    = Math.max(Math.min(client.width, client.height) * 0.8, 1)
        let distance = .radius * 3.2 / .zoomFactor()
        painter.setParams(.Antialiased)

        .projected.clear()
        for &mesh in .scene.meshes
        {
            for &triangle in mesh.triangles
            {
                var projected: ProjectedTriangle
                projected.depth = 0
                for corner in 3'u32
                {
                    let vertexIndex = corner == 0 ? triangle.a : corner == 1 ? triangle.b : triangle.c
                    let source      = mesh.vertices[vertexIndex].position
                    let vertex      = source - .center
                    let x           = vertex.x * Math.cos(.yaw) + vertex.z * Math.sin(.yaw)
                    let z           = -vertex.x * Math.sin(.yaw) + vertex.z * Math.cos(.yaw)
                    let y           = vertex.y * Math.cos(.pitch) - z * Math.sin(.pitch)
                    let depth       = Math.max(distance + vertex.y * Math.sin(.pitch) + z * Math.cos(.pitch), .radius * 0.15)
                    projected.points[corner] = Math.Vector2{client.x + client.width * 0.5 + .pan.x + x * (focal / depth),
                                                            client.y + client.height * 0.5 + .pan.y - y * (focal / depth)}
                    projected.depth += depth / 3
                }

                .projected.add(#move projected)
            }
        }

        .projected.sort(func(a, b) => b.depth <=> a.depth)
        for &triangle in .projected
        {
            let points = triangle.points
            painter.fillPolygon(points, Brush.createSolid(colors.softText))
            painter.drawLine(points[0].x, points[0].y, points[1].x, points[1].y, colors.line, metrics.separator_HairlineSize)
            painter.drawLine(points[1].x, points[1].y, points[2].x, points[2].y, colors.line, metrics.separator_HairlineSize)
            painter.drawLine(points[2].x, points[2].y, points[0].x, points[0].y, colors.line, metrics.separator_HairlineSize)
        }
    }
}

// Creates the integrated scene viewer and leaves file reading on the host's cancellable worker.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}

impl Panel
{
    // Shows scene structure and source-space dimensions on demand.
    mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        data.add(.Custom, Format.toString(texts().ui_Meshes, .scene.meshes.count))
        data.add(.Custom, Format.toString(texts().ui_Nodes, .scene.nodes.count))
        data.add(.Custom, Format.toString(texts().ui_Vertices, .vertexCount()))
        data.add(.Custom, Format.toString(texts().ui_Triangles, .triangleCount()))
        if not .scene.bounds.isEmpty
        {
            let size = .scene.bounds.max - .scene.bounds.min
            data.add(.Dimensions, Format.toString("% × % × %", size.x, size.y, size.z))
        }

        data.describe(sheet)
    }
}

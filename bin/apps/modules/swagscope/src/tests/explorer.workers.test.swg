#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// All slots schedule distinct visible tiles; cancelled generations never publish stale textures.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    var files, keys: Array'String
    defer
    {
        for file in files do
            catch File.delete(file[])
        for key in keys do
            catch File.delete(key[])
    }

    var image = Image.create(24, 18, .RGB8)
    image.fill(Color.fromRgb(56, 189, 248))
    for index in ExplorerWorkerCount
    {
        let file = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("parallel-thumbnail-%.txt", index))
        discard expect File.writeAllText(file, "cached preview")
        let key = expect ThumbnailCache.key(file, settings: ThumbnailSettings.capture(window))
        expect ThumbnailCache.write(key, &image)
        files.add(file)
        keys.add(key)
        explorer.entries.add({name: Path.fileName(file) orelse file.toString(), path: file})
    }

    explorer.setMode(.Medium)
    window.applyLayout()
    explorer.requestPreview()
    for &preview, index in explorer.previews do
        Swag.assert(preview.started and preview.index == index)
    explorer.hide()
    explorer.leave()
    for &preview in explorer.previews do
        preview.task.wait()
    for 100
    {
        host.pump()
        var busy = false
        for &preview in explorer.previews do
            busy = busy or preview.started
        if not busy do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(explorer.cached.isEmpty())

    explorer.show()
    explorer.requestPreview()
    for &preview in explorer.previews do
        preview.task.wait()
    for 100
    {
        host.pump()
        var busy = false
        for &preview in explorer.previews do
            busy = busy or preview.started
        if not busy do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(explorer.cached.count == ExplorerWorkerCount)
    for &entry in explorer.entries do
        Swag.assert(entry.texture.isValid())
}

// Each standard spinner animates on its own window until a completed preview replaces it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.entries.add({name: "Loading.txt", attempted: true})
    explorer.fill()
    let preview = &explorer.previews[0]
    preview.index      = 0
    preview.generation = explorer.generation
    preview.submit(func() {})
    let first = host.render(window)
    Swag.assert(explorer.grid.spinners[0].isLocallyVisible())
    let second = host.render(window)
    var changed: u32
    let rect   = explorer.grid.spinners[0].surfaceRect()
    for y in cast(s32, rect.height)
    {
        for x in cast(s32, rect.width)
        {
            let px = cast(s32, rect.x) + x
            let py = cast(s32, rect.y) + y
            if first.pixelColor(px, py) != second.pixelColor(px, py) do
                changed += 1
        }
    }

    Swag.assert(changed > 0)

    preview.wait()
    var image = Image.create(24, 18, .RGB8)
    image.fill(Color.fromRgb(56, 189, 248))
    explorer.entries[0].texture = host.app.renderer.addImage(&image)
    explorer.grid.invalidate()
    discard host.render(window)
    Swag.assert(not explorer.grid.spinners[0].isLocallyVisible())
}

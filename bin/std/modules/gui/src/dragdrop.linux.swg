#global if #os == Swag.TargetOs.Linux

using Core, Pixel

namespace LinuxDrag
{
    // XDND state belongs to the surface receiving the gesture. Selection storage is copied;
    // source windows and the active application are borrowed only until Leave or Finished.
    struct Target
    {
        source: u32
        version: u32
        selection: u32
        formats: Array'u32
        data: DragData
        position: Math.Point
        modifiers: Input.KeyModifiers
        allowed: DropEffect
        effect: DropEffect
        loaded: bool
    }

    struct Source
    {
        window: u32
        data: *DragData?
        target: u32
        proxy: u32
        version: u32
        allowed: DropEffect
        effect: DropEffect
        status: bool
        finished: bool
        success: bool
    }

    var activeSource: *Source?

    func property(context: *LinuxDesktop.Context, window, atom: u32)->LinuxSelection.Value
    {
        var result: #returntype
        let reply = context.xcb_get_property_reply(unwrap context.connection,
                                                     context.xcb_get_property(unwrap context.connection, 0, window, atom, 0, 0, 16384), null)
        if not reply do
            return result
        defer Linux.free(reply)
        let count = context.xcb_get_property_value_length(reply)
        if reply.type == 0 or reply.bytes_after != 0 or count < 0 or count > 65536 do
            return result
        result.type = reply.type
        result.format = reply.format
        result.valid = true
        if count do
            result.bytes.add(Swag.makeSlice(cast(const [*]u8, context.xcb_get_property_value(reply)), cast(u64, count)))
        return result
    }

    func send(context: *LinuxDesktop.Context, recipient, window: u32, name: string, data: [5]u32)->bool
    {
        catch
        {
            with var packet: Linux.xcb_client_message_event_t
            {
                .response_type = Linux.XCB_CLIENT_MESSAGE
                .format = 32
                .window = window
                .type = try LinuxDesktop.atom(context, name)
                .data = data
            }
            try LinuxDesktop.check(context, context.xcb_send_event_checked(unwrap context.connection, 0, recipient, 0,
                                                                           cast(const [*]u8, &packet)))
            return true
        }
        return false
    }

    func effectAtom(context: *LinuxDesktop.Context, effect: DropEffect)->u32
    {
        switch effect
        {
        case .Copy: return catch LinuxDesktop.atom(context, "XdndActionCopy")
        case .Move: return catch LinuxDesktop.atom(context, "XdndActionMove")
        case .Link: return catch LinuxDesktop.atom(context, "XdndActionLink")
        }
        return 0
    }

    func atomEffect(context: *LinuxDesktop.Context, atom: u32)->DropEffect
    {
        if atom == effectAtom(context, .Copy) do
            return .Copy
        if atom == effectAtom(context, .Move) do
            return .Move
        if atom == effectAtom(context, .Link) do
            return .Link
        return .None
    }

    func modifiers(mask: u16)->Input.KeyModifiers
    {
        var result: #returntype
        if mask & 1 do
            result |= .Shift
        if mask & 4 do
            result |= .Control
        if mask & 8 do
            result |= .Alt
        return result
    }

    func hexadecimal(byte: u8)->s32
    {
        if byte >= '0' and byte <= '9' do
            return byte - '0'
        if byte >= 'a' and byte <= 'f' do
            return byte - 'a' + 10
        if byte >= 'A' and byte <= 'F' do
            return byte - 'A' + 10
        return -1
    }

    func decodeFiles(data: *DragData, bytes: const [..]u8)
    {
        for line in Tokenize.split(cast(string, bytes), '\n'u8)
        {
            let uri = Latin1.trim(line)
            var offset: u64
            if Utf8.startsWith(uri, "file://localhost/") do
                offset = 16
            elif Utf8.startsWith(uri, "file:///") do
                offset = 7
            else do
                continue
            var path: String
            var valid = true
            while offset < uri.count
            {
                var byte = uri[offset]
                if byte == '%'
                {
                    if offset + 2 >= uri.count
                    {
                        valid = false
                        break
                    }
                    let high = hexadecimal(uri[offset + 1])
                    let low = hexadecimal(uri[offset + 2])
                    if high < 0 or low < 0
                    {
                        valid = false
                        break
                    }
                    byte = cast(u8, high * 16 + low)
                    offset += 2
                }
                if byte == 0
                {
                    valid = false
                    break
                }
                path.append(byte)
                offset += 1
            }
            if valid and not path.isEmpty() and Utf8.isValid(path.toString()) do
                data.addFile(#move path)
        }
    }

    func encodeFiles(data: *DragData)->String
    {
        var result: #returntype
        const Digits = "0123456789ABCDEF"
        for path in data.files
        {
            if not Path.isRooted(path.toString()) do
                continue
            result += "file://"
            for byte in path.toString()
            {
                if (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or
                   (byte >= '0' and byte <= '9') or byte == '/' or byte == '-' or byte == '_' or byte == '.' or byte == '~' do
                    result.append(byte)
                else
                {
                    result += '%'
                    result.append(Digits[byte >> 4])
                    result.append(Digits[byte & 15])
                }
            }
            result += "\r\n"
        }
        return result
    }

    func hasFormat(target: *Target, format: u32)->bool
    {
        for offered in target.formats where offered == format do
            return true
        return false
    }

    func load(target: *Target)
    {
        if target.loaded do
            return
        target.loaded = true
        if activeSource and activeSource.window == target.source and activeSource.data
        {
            target.data = activeSource.data[]
            return
        }
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            let utf8 = try LinuxSelection.atom("UTF8_STRING")
            let plain = try LinuxSelection.atom("text/plain;charset=utf-8")
            let uri = try LinuxSelection.atom("text/uri-list")
            let png = try LinuxSelection.atom("image/png")
            let contents = try LinuxSelection.atom("application/x-swag-drag-contents")
            if hasFormat(target, contents)
            {
                let metadata = LinuxSelection.read(target.selection, contents)
                if metadata.valid and metadata.type == contents and metadata.format == 8
                {
                    var stream = ByteStream.openRead(metadata.bytes.toSlice())
                    let count = try stream.readLittleEndian'u32()
                    if count <= 1024
                    {
                        for index in count
                        {
                            let name = try stream.readSizedString(65535)
                            let selection = target.selection
                            let nativeTarget = try LinuxSelection.atom(Format.toString("application/x-swag-drag-content-%", index).toString())
                            target.data.addContent(name, func|selection, nativeTarget|()->Array'u8
                            {
                                LinuxSelection.mutex.lock()
                                defer LinuxSelection.mutex.unlock()
                                let value = LinuxSelection.read(selection, nativeTarget)
                                if value.valid and value.type == nativeTarget and value.format == 8 do
                                    return value.bytes
                                return {}
                            })
                        }
                    }
                }
            }
            for format in [utf8, plain, uri, png]
            {
                if not hasFormat(target, format) do
                    continue
                if format == plain and target.data.hasText() do
                    continue
                let value = LinuxSelection.read(target.selection, format)
                if not value.valid or value.format != 8 or value.type != format do
                    continue
                if format == uri do
                    decodeFiles(&target.data, value.bytes.toSlice())
                elif format == png do
                    target.data.setImage("drag.png", value.bytes.toSlice())
                elif Utf8.isValid(value.bytes.toSlice()) do
                    target.data.setText(String.from(cast(string, value.bytes.toSlice())))
            }
        }
    }
}

internal func dispatchDragNativeEvent(surface: *Surface, event: *Linux.xcb_generic_event_t)->bool
{
    if event.response_type & 0x7F != Linux.XCB_CLIENT_MESSAGE do
        return false
    let packet = cast(*Linux.xcb_client_message_event_t, cast(*void, event))
    if packet.format != 32 do
        return false
    let context = catch LinuxDesktop.ensure()
    if not context do
        return false
    if packet.type == catch LinuxDesktop.atom(context, "XdndStatus")
    {
        let source = LinuxDrag.activeSource
        if source and packet.window == source.window and packet.data[0] == source.target
        {
            source.status = true
            source.effect = packet.data[1] & 1 ? LinuxDrag.atomEffect(context, packet.data[4]) : DropEffect.None
            if not source.allowed.has(source.effect) do
                source.effect = .None
        }
        return true
    }
    if packet.type == catch LinuxDesktop.atom(context, "XdndFinished")
    {
        let source = LinuxDrag.activeSource
        if source and packet.window == source.window and packet.data[0] == source.target
        {
            source.finished = true
            source.success = source.version < 5 or (packet.data[1] & 1) != 0
            if source.version >= 5 do
                source.effect = LinuxDrag.atomEffect(context, packet.data[2])
            if not source.allowed.has(source.effect) do
                source.success = false
        }
        return true
    }
    if packet.window != surface.windowId do
        return false
    let target = &surface.dropTarget
    if packet.type == catch LinuxDesktop.atom(context, "XdndEnter")
    {
        if target.source do
            surface.app.dragLeave(&target.data)
        Swag.drop(target, 1)
        Swag.init(target, 1)
        target.version = packet.data[1] >> 24
        if target.version < 3 or target.version > 5 do
            return true
        target.source = packet.data[0]
        target.selection = catch LinuxDesktop.atom(context, "XdndSelection")
        if packet.data[1] & 1
        {
            let formats = LinuxDrag.property(context, target.source, catch LinuxDesktop.atom(context, "XdndTypeList"))
            if formats.valid and formats.type == 4 and formats.format == 32 and formats.bytes.count % 4 == 0 do
                target.formats.add(Swag.makeSlice(cast(const [*]u32, formats.bytes.storage()), formats.bytes.count / 4))
        }
        else do
            for index in 2 until 5 where packet.data[index] != 0 do
                target.formats.add(packet.data[index])
        let actions = LinuxDrag.property(context, target.source, catch LinuxDesktop.atom(context, "XdndActionList"))
        if actions.valid and actions.type == 4 and actions.format == 32 and actions.bytes.count % 4 == 0
        {
            let atoms = cast(const [*]u32, actions.bytes.storage())
            for index in actions.bytes.count / 4 do
                target.allowed |= LinuxDrag.atomEffect(context, atoms[index])
        }
        return true
    }
    if packet.data[0] != target.source or target.source == 0 do
        return false
    if packet.type == catch LinuxDesktop.atom(context, "XdndLeave")
    {
        surface.app.dragLeave(&target.data)
        target.data.clear()
        target.source = 0
        return true
    }
    if packet.type == catch LinuxDesktop.atom(context, "XdndPosition")
    {
        target.position = {cast(f32, cast(s16, packet.data[2] >> 16)), cast(f32, cast(s16, packet.data[2] & 0xFFFF))}
        let pointer = context.xcb_query_pointer_reply(unwrap context.connection,
                                                       context.xcb_query_pointer(unwrap context.connection, surface.windowId), null)
        if pointer
        {
            target.modifiers = LinuxDrag.modifiers(pointer.mask)
            Linux.free(pointer)
        }
        let action = LinuxDrag.atomEffect(context, packet.data[4])
        if target.allowed == .None do
            target.allowed = action
        LinuxDrag.load(target)
        target.effect = surface.app.dragUpdate(surface, target.position, &target.data, target.allowed, target.modifiers)
        if not target.allowed.has(target.effect) do
            target.effect = .None
        // Request every position; the target's hit testing can change within the surface.
        discard LinuxDrag.send(context, target.source, target.source, "XdndStatus",
                                [surface.windowId, target.effect == .None ? 2'u32 : 3'u32, 0, 0, LinuxDrag.effectAtom(context, target.effect)])
        return true
    }
    if packet.type == catch LinuxDesktop.atom(context, "XdndDrop")
    {
        LinuxDrag.load(target)
        let effect = surface.app.dragDrop(surface, target.position, &target.data, target.allowed, target.modifiers)
        let accepted = effect != .None and target.allowed.has(effect)
        discard LinuxDrag.send(context, target.source, target.source, "XdndFinished",
                                [surface.windowId, accepted ? 1'u32 : 0'u32, accepted ? LinuxDrag.effectAtom(context, effect) : 0'u32, 0, 0])
        target.source = 0
        target.data.clear()
        return true
    }
    return false
}

internal impl Surface
{
    mtd registerDropTarget()
    {
        if .windowId == 0 or .dropTargetActive do
            return
        catch
        {
            let context = try LinuxDesktop.ensure()
            let version = 5'u32
            try LinuxDesktop.check(context, context.xcb_change_property_checked(unwrap context.connection, 0, .windowId,
                                                                                 try LinuxDesktop.atom(context, "XdndAware"), 4, 32, 1, &version))
            .dropTargetActive = true
        }
    }

    mtd revokeDropTarget()
    {
        if .app.dragEnterWnd and .app.dragEnterWnd.surface == me do
            .app.dragEnterWnd = null
        .dropTarget.data.clear()
        .dropTarget.source = 0
        .dropTargetActive = false
    }
}

namespace LinuxDrag
{
    struct Preview
    {
        library: *void?
        cursorLibrary: *void?
        display: *void?
        cursor: u32
        late closeDisplay: Linux.XCloseDisplay_fn
        late freeCursor: Linux.XFreeCursor_fn
    }

    impl Preview
    {
        mtd clear()
        {
            if .display
            {
                if .cursor do
                    discard .freeCursor(unwrap .display, .cursor)
                discard .closeDisplay(unwrap .display)
            }
            if .cursorLibrary do
                discard Linux.dlclose(unwrap .cursorLibrary)
            if .library do
                discard Linux.dlclose(unwrap .library)
            .cursor = 0
            .display = null
            .cursorLibrary = null
            .library = null
        }

        func create(picture: const *Image?)->Preview
        {
            var result: #returntype
            if not picture or not picture.isValid() do
                return result
            catch
            {
                result.library = Linux.dlopen("libX11.so.6".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
                result.cursorLibrary = Linux.dlopen("libXcursor.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
                if not result.library or not result.cursorLibrary
                {
                    result.clear()
                    return {}
                }
                let open = try LinuxDesktop.symbol'Linux.XOpenDisplay_fn(unwrap result.library, "XOpenDisplay")
                result.closeDisplay = try LinuxDesktop.symbol'Linux.XCloseDisplay_fn(unwrap result.library, "XCloseDisplay")
                result.freeCursor = try LinuxDesktop.symbol'Linux.XFreeCursor_fn(unwrap result.library, "XFreeCursor")
                let sync = try LinuxDesktop.symbol'Linux.XSync_fn(unwrap result.library, "XSync")
                let createImage = try LinuxDesktop.symbol'Linux.XcursorImageCreate_fn(unwrap result.cursorLibrary, "XcursorImageCreate")
                let destroyImage = try LinuxDesktop.symbol'Linux.XcursorImageDestroy_fn(unwrap result.cursorLibrary, "XcursorImageDestroy")
                let load = try LinuxDesktop.symbol'Linux.XcursorImageLoadCursor_fn(unwrap result.cursorLibrary, "XcursorImageLoadCursor")
                result.display = open(null)
                if not result.display
                {
                    result.clear()
                    return {}
                }
                let scale = Math.min(1.0'f32, 64.0 / cast(f32, Math.max(picture.width, picture.height)))
                let width = Math.max(1, cast(s32, picture.width * scale))
                let height = Math.max(1, cast(s32, picture.height * scale))
                let nativeImage = createImage(width, height)
                if not nativeImage
                {
                    result.clear()
                    return {}
                }
                defer destroyImage(unwrap nativeImage)
                nativeImage.xhot = cast(u32, width / 2)
                nativeImage.yhot = cast(u32, height / 2)
                for y in height do
                    for x in width
                    {
                        let color = picture.pixelColor(cast(s32, cast(s64, x) * picture.width / width),
                                                       cast(s32, cast(s64, y) * picture.height / height))
                        let alpha = cast(u32, color.a)
                        nativeImage.pixels[y * width + x] = (alpha << 24) |
                            ((cast(u32, color.r) * alpha / 255) << 16) |
                            ((cast(u32, color.g) * alpha / 255) << 8) | (cast(u32, color.b) * alpha / 255)
                    }
                result.cursor = cast(u32, load(unwrap result.display, nativeImage))
                discard sync(unwrap result.display, 0)
                return result
            }
            result.clear()
            return {}
        }
    }

    func destination(context: *LinuxDesktop.Context, child: u32)->Source
    {
        var result: #returntype
        var window = child
        // QueryPointer gives one child at a time, including window-manager frames.
        for 64
        {
            if window == 0 do
                return result
            let pointer = context.xcb_query_pointer_reply(unwrap context.connection,
                                                           context.xcb_query_pointer(unwrap context.connection, window), null)
            if not pointer do
                return result
            let next = pointer.child
            Linux.free(pointer)
            if next == 0 do
                break
            window = next
        }
        let awareAtom = catch LinuxDesktop.atom(context, "XdndAware")
        let proxyAtom = catch LinuxDesktop.atom(context, "XdndProxy")
        for 64
        {
            let aware = property(context, window, awareAtom)
            if aware.valid and aware.type == 4 and aware.format == 32 and aware.bytes.count >= 4
            {
                let version = cast(const [*]u32, aware.bytes.storage())[0]
                if version >= 3
                {
                    result.target = window
                    result.proxy = window
                    result.version = Math.min(version, 5'u32)
                    let proxy = property(context, window, proxyAtom)
                    if proxy.valid and proxy.type == 33 and proxy.format == 32 and proxy.bytes.count == 4
                    {
                        let id = cast(const [*]u32, proxy.bytes.storage())[0]
                        let verify = property(context, id, proxyAtom)
                        if verify.valid and verify.type == 33 and verify.format == 32 and verify.bytes.count == 4 and
                           cast(const [*]u32, verify.bytes.storage())[0] == id do
                            result.proxy = id
                    }
                    return result
                }
            }
            let tree = context.xcb_query_tree_reply(unwrap context.connection,
                                                      context.xcb_query_tree(unwrap context.connection, window), null)
            if not tree do
                return result
            let parent = tree.parent
            Linux.free(tree)
            if parent == 0 or parent == window do
                return result
            window = parent
        }
        return result
    }

    func fulfill(data: *DragData, selection, png: u32, contents: const [..]u32)
    {
        LinuxSelection.mutex.lock()
        let requested = LinuxSelection.requested(selection)
        LinuxSelection.mutex.unlock()
        if requested == 0 do
            return
        var bytes: Array'u8
        if requested == png
        {
            let image = data.image()
            if image do
                bytes = catch image.encodeToBytes("drag.png", Png.EncodeOptions{compressionLevel: .BestSpeed})
        }
        else do
            for target, index in contents where target == requested
            {
                bytes.add(data.contentData(index))
                break
            }
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        LinuxSelection.complete(selection, requested, bytes.toSlice())
    }
}

impl Wnd
{
    // Runs an XDND gesture until release, cancellation or application shutdown.
    //
    // Text, local file URIs and PNG images interoperate with other X11 applications. Named
    // content uses the Swag content targets and is produced only when a recipient asks.
    // The payload and optional picture are borrowed for this call. A rejected or cancelled
    // drop returns None; successful drops return the recipient's allowed effect.
    public mtd startDrag(data: *DragData, allowed = DropEffect.Copy, picture: const *Pixel.Image? = null)->DropEffect
    {
        let surface = .surface
        if not surface or not surface.app.renderer.needsNativeWindow() or surface.windowId == 0 or
           allowed == .None or LinuxDrag.activeSource do
            return .None
        if not data.hasFiles() and not data.hasContents() and not data.hasText() and not data.hasImage() do
            return .None
        let context = catch LinuxDesktop.ensure() { return .None; }
        if .app().mouseCapture() == me do
            .releaseMouse()
        let connection = unwrap context.connection
        let originalCursor = context.currentCursor
        defer Cursor.activate(Cursor.from(originalCursor))
        let changeCursor = catch LinuxDesktop.symbol'Linux.xcb_change_active_pointer_grab_checked_fn(unwrap context.library, "xcb_change_active_pointer_grab_checked") { return .None; }
        var preview = LinuxDrag.Preview.create(picture orelse data.image())
        defer preview.clear()
        let grabbed = context.xcb_grab_pointer_reply(connection,
                                                      context.xcb_grab_pointer(connection, 0, surface.windowId, 0, 1, 1, 0, preview.cursor, 0), null)
        if not grabbed do
            return .None
        let status = grabbed.status
        Linux.free(grabbed)
        if status != 0 do
            return .None
        defer discard catch LinuxDesktop.check(context, context.xcb_ungrab_pointer_checked(connection, 0))

        var selection: u32
        var sourceWindow: u32
        var png: u32
        var formats: Array'u32
        var contents: Array'u32
        LinuxSelection.mutex.lock()
        catch
        {
            try LinuxSelection.ensure()
            sourceWindow = LinuxSelection.service.window
            LinuxSelection.service.clientMessages.clear()
            selection = try LinuxSelection.atom("XdndSelection")
            LinuxSelection.clear(selection)
            if data.hasText()
            {
                let utf8 = try LinuxSelection.atom("UTF8_STRING")
                if LinuxSelection.publish(selection, utf8, data.text.toString()) do
                    formats.add(utf8)
                let plain = try LinuxSelection.atom("text/plain;charset=utf-8")
                if LinuxSelection.publish(selection, plain, data.text.toString()) do
                    formats.add(plain)
            }
            if data.hasFiles()
            {
                let uri = try LinuxSelection.atom("text/uri-list")
                let encoded = LinuxDrag.encodeFiles(data)
                if LinuxSelection.publish(selection, uri, encoded.toString()) do
                    formats.add(uri)
            }
            if data.hasImage()
            {
                png = try LinuxSelection.atom("image/png")
                if LinuxSelection.announce(selection, png) do
                    formats.add(png)
            }
            if data.hasContents() and data.contents.count <= 1024
            {
                var metadata: Array'u8
                var stream = ByteStream.openWrite(&metadata)
                stream.writeLittleEndian(cast(u32, data.contents.count))
                for content, index in data.contents
                {
                    stream.writeSizedString(content.name.toString())
                    let target = try LinuxSelection.atom(Format.toString("application/x-swag-drag-content-%", index).toString())
                    if LinuxSelection.announce(selection, target) do
                        contents.add(target)
                }
                let target = try LinuxSelection.atom("application/x-swag-drag-contents")
                if LinuxSelection.publish(selection, target, metadata.toSlice()) do
                    formats.add(target)
            }
        }
        LinuxSelection.mutex.unlock()
        defer
        {
            LinuxSelection.mutex.lock()
            if selection do
                LinuxSelection.release(selection)
            LinuxSelection.mutex.unlock()
        }
        if formats.isEmpty() do
            return .None
        catch
        {
            try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, sourceWindow,
                                                                                 try LinuxDesktop.atom(context, "XdndTypeList"), 4, 32,
                                                                                 cast(u32, formats.count), formats.storage()))
            var actions: Array'u32
            for effect in [DropEffect.Copy, DropEffect.Move, DropEffect.Link] where allowed.has(effect) do
                actions.add(LinuxDrag.effectAtom(context, effect))
            try LinuxDesktop.check(context, context.xcb_change_property_checked(connection, 0, sourceWindow,
                                                                                 try LinuxDesktop.atom(context, "XdndActionList"), 4, 32,
                                                                                 cast(u32, actions.count), actions.storage()))
        }
        with var source: LinuxDrag.Source
        {
            .window = sourceWindow
            .data = data
            .allowed = allowed
        }
        LinuxDrag.activeSource = &source
        defer LinuxDrag.activeSource = null
        var sentPosition: u32 = Swag.U32.Max
        var sentAction: u32
        var awaiting: bool
        var dropped: bool
        var released: bool
        var deadline: u64
        defer if source.target and not dropped do
            discard LinuxDrag.send(context, source.proxy, source.target, "XdndLeave", [source.window, 0, 0, 0, 0])
        for
        {
            LinuxDrag.fulfill(data, selection, png, contents.toSlice())
            var messages: Array'Linux.xcb_client_message_event_t
            LinuxSelection.mutex.lock()
            messages.add(LinuxSelection.service.clientMessages.toSlice())
            LinuxSelection.service.clientMessages.clear()
            LinuxSelection.mutex.unlock()
            for &message in messages do
                discard dispatchDragNativeEvent(surface, cast(*Linux.xcb_generic_event_t, cast(*void, message)))
            surface.app.sendSystemEvents()
            surface.app.runClockFrame()
            if surface.app.mustQuit or surface.wnd.isPendingDestroy or Input.Keyboard.isKeyPressed(.Escape) do
                return .None
            let shape = source.effect == .None ? CursorShape.No : source.effect == .Move ? CursorShape.Move : CursorShape.Hand
            Cursor.activate(Cursor.from(shape))
            let cursor = preview.cursor != 0 and source.effect != .None ? preview.cursor : context.cursors[shape]
            discard catch LinuxDesktop.check(context, changeCursor(connection, cursor, 0, 0))
            let now = Time.monotonicMilliseconds()
            if dropped
            {
                if source.finished do
                    return source.success ? source.effect : DropEffect.None
                if now >= deadline do
                    return .None
                Threading.Thread.sleep(Time.Duration.fromMilliseconds(5))
                continue
            }
            let pointer = context.xcb_query_pointer_reply(connection, context.xcb_query_pointer(connection, context.screen.root), null)
            if not pointer do
                return .None
            let child = pointer.child
            let position = (cast(u32, cast(u16, pointer.root_x)) << 16) | cast(u16, pointer.root_y)
            let mask = pointer.mask
            Linux.free(pointer)
            let destination = LinuxDrag.destination(context, child)
            if destination.target != source.target
            {
                if source.target do
                    discard LinuxDrag.send(context, source.proxy, source.target, "XdndLeave", [source.window, 0, 0, 0, 0])
                source.target = destination.target
                source.proxy = destination.proxy
                source.version = destination.version
                source.effect = .None
                source.status = false
                awaiting = false
                sentPosition = Swag.U32.Max
                if source.target
                {
                    var message: [5]u32
                    message[0] = source.window
                    message[1] = source.version << 24
                    if formats.count > 3 do
                        message[1] |= 1
                    else do
                        for format, index in formats do
                            message[index + 2] = format
                    discard LinuxDrag.send(context, source.proxy, source.target, "XdndEnter", message)
                }
            }
            if source.status
            {
                awaiting = false
                source.status = false
            }
            let action = LinuxDrag.effectAtom(context, pickDropEffect(allowed, LinuxDrag.modifiers(mask)))
            if source.target and not awaiting and (position != sentPosition or action != sentAction)
            {
                source.effect = .None
                if not LinuxDrag.send(context, source.proxy, source.target, "XdndPosition", [source.window, 0, position, 0, action]) do
                    return .None
                sentPosition = position
                sentAction = action
                awaiting = true
                deadline = now + 1000
            }
            if (mask & (1 << 8)) == 0 and not released
            {
                released = true
                if not awaiting do
                    deadline = now + 1000
            }
            if released
            {
                if awaiting and now < deadline
                {
                    Threading.Thread.sleep(Time.Duration.fromMilliseconds(5))
                    continue
                }
                if awaiting or source.effect == .None or source.target == 0 do
                    return .None
                if not LinuxDrag.send(context, source.proxy, source.target, "XdndDrop", [source.window, 0, 0, 0, 0]) do
                    return .None
                dropped = true
                deadline = now + LinuxSelection.TimeoutMs
            }
            elif awaiting and now >= deadline
            {
                awaiting = false
                source.effect = .None
            }
            Threading.Thread.sleep(Time.Duration.fromMilliseconds(5))
        }
    }

    // Tests an eight-pixel physical movement threshold used by X11 desktop toolkits.
    public mtd const exceedsDragThreshold(origin, current: Math.Point)->bool
    {
        let scale = .surface ? .surface.dpiScale : 1.0
        return Math.abs(current.x - origin.x) * scale >= 8 or Math.abs(current.y - origin.y) * scale >= 8
    }
}

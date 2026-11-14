#global if #os == Swag.TargetOs.Linux
#global public

using Core, Pixel

#[Swag.Inline]
private func copyX11BgraRow(input: const [*] u8, output: [*] u8, width: u64, opaque: Math.Simd.U32x4)
{
    for group in width / 4
    {
        let offset = group * 16
        let pixels = cast #bit(Math.Simd.U32x4, Math.Simd.load(input + offset))
        Math.Simd.store(output + offset, cast #bit(Math.Simd.U8x16, pixels | opaque))
    }
    for pixel in width % 4
    {
        let offset = (width / 4 * 4 + pixel) * 4
        Memory.copy(output + offset, input + offset, 3)
        output[offset + 3] = 255
    }
}

// XFixes request headers are filled by xcb_send_request. The remaining words
// are the protocol payload; both requests fit in one iovec.
private struct XfixesVersionRequest
{
    header: u32
    major:  u32
    minor:  u32
}

private struct XfixesCursorRequest
{
    header: u32
}

#assert(#sizeof(XfixesVersionRequest) == 12)
#assert(#sizeof(XfixesCursorRequest) == 4)

// Owns an independent X11 connection for desktop capture and best-effort window queries.
// The GUI event queue remains owned by Gui; capture never consumes its events.
#[Swag.NoDoc, Swag.NoCopy]
struct X11Capture
{
    library:              *void?
    fixesExtension:       Linux.xcb_extension_t
    fixesReady:           bool
    shmExtension:         Linux.xcb_extension_t
    shmData:              *void?
    shmSize:              u64
    shmId:                s32
    shmSegment:           u32
    shmDisabled:          bool
    connection:           *void?
    screen:               Linux.xcb_screen_t
    screenPointer:        const *Linux.xcb_screen_t?
    setup:                const *Linux.xcb_setup_t?
    late disconnect:      Linux.xcb_disconnect_fn
    late getGeometry:     Linux.xcb_get_geometry_fn
    late geometryReply:   Linux.xcb_get_geometry_reply_fn
    late getAttributes:   Linux.xcb_get_window_attributes_fn
    late attributesReply: Linux.xcb_get_window_attributes_reply_fn
    late translate:       Linux.xcb_translate_coordinates_fn
    late translateReply:  Linux.xcb_translate_coordinates_reply_fn
    late queryTree:       Linux.xcb_query_tree_fn
    late treeReply:       Linux.xcb_query_tree_reply_fn
    late treeChildren:    Linux.xcb_query_tree_children_fn
    late intern:          Linux.xcb_intern_atom_fn
    late internReply:     Linux.xcb_intern_atom_reply_fn
    late getProperty:     Linux.xcb_get_property_fn
    late propertyReply:   Linux.xcb_get_property_reply_fn
    late propertyValue:   Linux.xcb_get_property_value_fn
}

impl X11Capture
{
    mtd const desktopWidth()->u16 => .screen.width_in_pixels
    mtd const desktopHeight()->u16 => .screen.height_in_pixels
    mtd const rootWindow()->u32 => .screen.root
    mtd const rootDepth()->u8 => .screen.root_depth
    mtd const nativeLibrary()->*void? => .library
    mtd const nativeConnection()->*void? => .connection
    mtd const cursorExtensionReady()->bool => .fixesReady
    mtd const usesSharedMemory()->bool => .shmData != null
    mtd const sharedMemorySize()->u64 => .shmSize

    func(T) symbol(library: *void, name: string)->T fail
    {
        let address = Linux.dlsym(library, name.buffer)
        if not address do
            fail Swag.SystemError{"X11 capture cannot resolve a required native function"}
        return cast(T, address)
    }

    func create()->X11Capture fail
    {
        var result: #returntype
        result.library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        if not result.library do
            fail Swag.SystemError{"desktop capture cannot load libxcb.so.1"}
        result.shmExtension.name = "MIT-SHM".buffer
        result.fixesExtension.name = "XFIXES".buffer
        let library = result.library
        result.disconnect = try symbol'Linux.xcb_disconnect_fn(library, "xcb_disconnect")
        let connect         = try symbol'Linux.xcb_connect_fn(library, "xcb_connect")
        let connectionError = try symbol'Linux.xcb_connection_has_error_fn(library, "xcb_connection_has_error")
        let getSetup        = try symbol'Linux.xcb_get_setup_fn(library, "xcb_get_setup")
        let roots           = try symbol'Linux.xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
        let nextScreen      = try symbol'Linux.xcb_screen_next_fn(library, "xcb_screen_next")
        var selected: s32
        result.connection = connect(null, &selected)
        if not result.connection or connectionError(result.connection) != 0 do
            fail Swag.SystemError{"desktop capture cannot connect to the X11 display"}
        result.setup = getSetup(result.connection)
        var screens = roots(result.setup)
        while selected > 0 and screens.rem > 0
        {
            nextScreen(&screens)
            selected -= 1
        }

        if screens.rem <= 0 or not screens.data do
            fail Swag.SystemError{"desktop capture cannot find the selected X11 screen"}
        result.screenPointer   = screens.data
        result.screen          = screens.data[]
        result.getGeometry     = try symbol'Linux.xcb_get_geometry_fn(library, "xcb_get_geometry")
        result.geometryReply   = try symbol'Linux.xcb_get_geometry_reply_fn(library, "xcb_get_geometry_reply")
        result.getAttributes   = try symbol'Linux.xcb_get_window_attributes_fn(library, "xcb_get_window_attributes")
        result.attributesReply = try symbol'Linux.xcb_get_window_attributes_reply_fn(library, "xcb_get_window_attributes_reply")
        result.translate       = try symbol'Linux.xcb_translate_coordinates_fn(library, "xcb_translate_coordinates")
        result.translateReply  = try symbol'Linux.xcb_translate_coordinates_reply_fn(library, "xcb_translate_coordinates_reply")
        result.queryTree       = try symbol'Linux.xcb_query_tree_fn(library, "xcb_query_tree")
        result.treeReply       = try symbol'Linux.xcb_query_tree_reply_fn(library, "xcb_query_tree_reply")
        result.treeChildren    = try symbol'Linux.xcb_query_tree_children_fn(library, "xcb_query_tree_children")
        result.intern          = try symbol'Linux.xcb_intern_atom_fn(library, "xcb_intern_atom")
        result.internReply     = try symbol'Linux.xcb_intern_atom_reply_fn(library, "xcb_intern_atom_reply")
        result.getProperty     = try symbol'Linux.xcb_get_property_fn(library, "xcb_get_property")
        result.propertyReply   = try symbol'Linux.xcb_get_property_reply_fn(library, "xcb_get_property_reply")
        result.propertyValue   = try symbol'Linux.xcb_get_property_value_fn(library, "xcb_get_property_value")
        return result
    }

    mtd opDrop()
    {
        .releaseSharedMemory()
        if .connection do
            .disconnect(.connection)
        if .library do
            discard Linux.dlclose(.library)
    }

    mtd atom(name: string, create: bool = false)->u32
    {
        let connection = unwrap .connection
        let reply      = .internReply(connection, .intern(connection, create ? 0'u8 : 1'u8,
                                                        cast(u16, name.count), name.buffer), null)
        if not reply do
            return 0
        defer Linux.free(reply)
        return reply.atom
    }

    mtd property(window: u32, name: string, format: u8, limit: u32 = 16384)->Array'u8
    {
        let connection = unwrap .connection
        let atom       = .atom(name)
        if not atom do
            return {}
        let reply = .propertyReply(connection,
                                   .getProperty(connection, 0, window, atom, 0, 0, (limit + 3) / 4),
                                   null)
        if not reply do
            return {}
        defer Linux.free(reply)
        if reply.format != format or reply.bytes_after != 0 do
            return {}
        let count = cast(u64, reply.value_len) * (format / 8)
        if count > limit do
            return {}
        var result: #returntype
        result.add(Swag.makeSlice(cast(const [*]u8, .propertyValue(reply)), count))
        return result
    }

    mtd textProperty(window: u32, name: string)->String
    {
        let bytes = .property(window, name, 8)
        let text  = cast(string, bytes.toSlice())
        if not Utf8.isValid(bytes.toSlice()) do
            return {}
        return String.from(text)
    }

    mtd windowRect(window: u32)->Math.Rectangle
    {
        let connection = unwrap .connection
        if not window do
            return {}
        let geometry = .geometryReply(connection, .getGeometry(connection, window), null)
        if not geometry do
            return {}
        defer Linux.free(geometry)
        let translated = .translateReply(connection,
                                         .translate(connection, window, .screen.root, 0, 0),
                                         null)
        if not translated do
            return {}
        defer Linux.free(translated)
        if not translated.same_screen do
            return {}
        var result: #returntype = {translated.dst_x, translated.dst_y, geometry.width, geometry.height}
        let frame = .property(window, "_NET_FRAME_EXTENTS", 32, 16)
        if frame.count == 16
        {
            var extents: [4] u32
            Memory.copy(&extents[0], frame.storage(), 16)

            // Window-manager decorations belong to the captured window. Ignore malformed
            // client properties rather than allowing an unbounded selection rectangle.
            if extents[0] <= .screen.width_in_pixels and
               extents[1] <= .screen.width_in_pixels and
               extents[2] <= .screen.height_in_pixels and
               extents[3] <= .screen.height_in_pixels
            {
                result.x      -= extents[0]
                result.y      -= extents[2]
                result.width  += extents[0] + extents[1]
                result.height += extents[2] + extents[3]
            }
        }

        return result
    }

    // Returns whether a window is mapped to the desktop; a minimized window is not viewable.
    mtd windowIsViewable(window: u32)->bool
    {
        let connection = unwrap .connection
        let attrs = .attributesReply(connection, .getAttributes(connection, window), null)
        if not attrs do
            return false
        let visible = attrs.map_state == 2
        Linux.free(attrs)
        return visible
    }

    mtd windowAt(ignore: u32, x, y: f32)->u32
    {
        let connection = unwrap .connection
        func contains(rect: Math.Rectangle, x, y: f32)->bool =>
            not rect.isEmpty() and
            x >= rect.x and
            y >= rect.y and
            x < rect.right() and
            y < rect.bottom()

        // EWMH clients are bottom-to-top, independent of decoration/reparenting frames.
        let clients = .property(.screen.root, "_NET_CLIENT_LIST_STACKING", 32, 262144)
        if clients.count % 4 == 0 and clients.count != 0
        {
            var index = clients.count / 4
            while index
            {
                index -= 1
                var window: u32
                Memory.copy(&window, &clients[index * 4], 4)
                if window == ignore do
                    continue
                let attrs = .attributesReply(connection, .getAttributes(connection, window), null)
                if not attrs do
                    continue
                let visible = attrs.map_state == 2
                Linux.free(attrs)
                if visible and contains(.windowRect(window), x, y) do
                    return window
            }

            return 0
        }

        // Unmanaged X servers (including Xvfb) have no EWMH list.
        let tree = .treeReply(connection, .queryTree(connection, .screen.root), null)
        if not tree do
            return 0
        defer Linux.free(tree)
        let children = .treeChildren(tree)
        var index    = cast(u32, tree.children_len)
        while index
        {
            index -= 1
            let window = children[index]
            if window == ignore do
                continue
            let attrs = .attributesReply(connection, .getAttributes(connection, window), null)
            if not attrs do
                continue
            let visible = attrs.map_state == 2
            Linux.free(attrs)
            if visible and contains(.windowRect(window), x, y) do
                return window
        }

        return 0
    }

    mtd activeWindow()->u32
    {
        let bytes = .property(.screen.root, "_NET_ACTIVE_WINDOW", 32, 4)
        if bytes.count != 4 do
            return 0
        var result: u32
        Memory.copy(&result, bytes.storage(), 4)
        return result
    }

    mtd windowInfo(window: u32)->{ title: String, className: String, processId: u32 }
    {
        var result: #returntype
        result.title = .textProperty(window, "_NET_WM_NAME")
        if result.title.isEmpty() do
            result.title = .textProperty(window, "WM_NAME")
        let classes = .property(window, "WM_CLASS", 8)
        var first: u64
        while first < classes.count and classes[first] != 0 do
            first += 1
        if first < classes.count
        {
            let start = first + 1
            var end   = start
            while end < classes.count and classes[end] != 0 do
                end += 1
            let value = classes.toSlice()[start until end]
            if Utf8.isValid(value) do
                result.className = cast(string, value)
        }

        let pid = .property(window, "_NET_WM_PID", 32, 4)
        if pid.count == 4 do
            Memory.copy(&result.processId, pid.storage(), 4)
        return result
    }

    mtd image(drawCursor: bool, x, y, width, height: s32)->Image fail
    {
        var result: Image
        try .imageInto(&result, drawCursor, x, y, width, height)
        return result
    }

    // libxcb fills the four-byte X11 header and routes the request through the
    // selected extension descriptor. Each wire request below is otherwise Swag data.
    private mtd extensionRequest(extension: *Linux.xcb_extension_t, wire: *void, size: u64,
                                 opcode: u8, isvoid, checked: bool)->u32
    {
        let send = cast(Linux.xcb_send_request_fn, unwrap Linux.dlsym(unwrap .library, "xcb_send_request".buffer))
        // xcb_send_request writes its request header into the two reserved slots
        // immediately before the payload vectors, so leave those slots at [0..2).
        var vectors: [4] Linux.xcb_iovec_t
        vectors[2].base   = wire
        vectors[2].length = size
        vectors[3].length = (4 - size % 4) % 4
        var descriptor: Linux.xcb_protocol_request_t
        descriptor.count  = 2
        descriptor.ext    = extension
        descriptor.opcode = opcode
        descriptor.isvoid = isvoid ? 1 : 0
        return send(unwrap .connection, checked ? 1 : 0, &vectors[2], &descriptor)
    }

    private mtd sharedRequest(wire: *void, size: u64, opcode: u8, isvoid, checked: bool)->u32 =>
        .extensionRequest(&.shmExtension, wire, size, opcode, isvoid, checked)

    // Keep one segment across frames. A failed MIT-SHM attach disables the optional
    // path for this connection, so remote X servers continue through GetImage.
    private mtd ensureSharedMemory(width, height: s32)->bool
    {
        if .shmDisabled do
            return false
        let needed = cast(u64, width) * cast(u64, height) * 4
        if .shmData and .shmSize >= needed do
            return true
        .releaseSharedMemory()
        let library   = unwrap .library
        let extension = cast(Linux.xcb_get_extension_data_fn, unwrap Linux.dlsym(library, "xcb_get_extension_data".buffer))
        let available = extension(unwrap .connection, &.shmExtension)
        if not available or not available.present
        {
            .disableSharedMemory()
            return false
        }

        let id = Linux.shmget(0, needed, 0x380)
        if id < 0
        {
            .disableSharedMemory()
            return false
        }
        let address = Linux.shmat(id, null, 0)
        if address == cast(*void, -1's64)
        {
            discard Linux.shmctl(id, 0, null)
            .disableSharedMemory()
            return false
        }

        let generate   = cast(Linux.xcb_generate_id_fn, unwrap Linux.dlsym(library, "xcb_generate_id".buffer))
        let check      = cast(Linux.xcb_request_check_fn, unwrap Linux.dlsym(library, "xcb_request_check".buffer))
        let connection = .connection
        let segment    = generate(connection)
        var wire: Linux.xcb_shm_attach_request_t
        wire.segment = segment
        wire.shmid   = cast(u32, id)
        let sequence = .sharedRequest(&wire, #sizeof(wire), 1, true, true)
        let error    = check(connection, {sequence})
        if error
        {
            Linux.free(error)
            discard Linux.shmdt(unwrap address)
            discard Linux.shmctl(id, 0, null)
            .disableSharedMemory()
            return false
        }

        .shmData    = address
        .shmSize    = needed
        .shmId      = id
        .shmSegment = segment
        // The segment is reclaimed after both X11 and this process detach.
        if Linux.shmctl(id, 0, null) != 0
        {
            .disableSharedMemory()
            return false
        }
        return true
    }

    mtd disableSharedMemory()
    {
        .releaseSharedMemory()
        .shmDisabled = true
    }

    private mtd releaseSharedMemory()
    {
        if not .shmData do
            return
        var wire: Linux.xcb_shm_detach_request_t
        wire.segment = .shmSegment
        discard .sharedRequest(&wire, #sizeof(wire), 2, true, false)
        discard Linux.shmdt(.shmData)
        discard Linux.shmctl(.shmId, 0, null)
        .shmData = null
        .shmSize = 0
    }

    // Reuses `target` storage across captures of the same rectangle.
    mtd imageInto(target: *Image, drawCursor: bool, x, y, width, height: s32) fail
    {
        let connection = unwrap .connection
        if x < 0 or
           y < 0 or
           x > 32767 or
           y > 32767 or
           width <= 0 or
           height <= 0 or
           cast(s64, x) + width > .screen.width_in_pixels or
           cast(s64, y) + height > .screen.height_in_pixels do
            fail Errors.BadParameterError{"capture rectangle lies outside the X11 screen"}
        let library    = unwrap .library
        let get        = try symbol'Linux.xcb_get_image_fn(library, "xcb_get_image")
        let reply      = try symbol'Linux.xcb_get_image_reply_fn(library, "xcb_get_image_reply")
        let data       = try symbol'Linux.xcb_get_image_data_fn(library, "xcb_get_image_data")
        let dataLength = try symbol'Linux.xcb_get_image_data_length_fn(library, "xcb_get_image_data_length")
        let formats    = try symbol'Linux.xcb_setup_pixmap_formats_iterator_fn(library, "xcb_setup_pixmap_formats_iterator")
        let formatNext = try symbol'Linux.xcb_format_next_fn(library, "xcb_format_next")
        let depths     = try symbol'Linux.xcb_screen_allowed_depths_iterator_fn(library, "xcb_screen_allowed_depths_iterator")
        let depthNext  = try symbol'Linux.xcb_depth_next_fn(library, "xcb_depth_next")
        let visuals    = try symbol'Linux.xcb_depth_visuals_iterator_fn(library, "xcb_depth_visuals_iterator")
        let visualNext = try symbol'Linux.xcb_visualtype_next_fn(library, "xcb_visualtype_next")
        var captured: *Linux.xcb_get_image_reply_t?
        var sharedSize: u64
        var shared = .ensureSharedMemory(width, height)
        if shared
        {
            var wire: Linux.xcb_shm_get_image_request_t
            wire.drawable   = .screen.root
            wire.x          = cast(s16, x)
            wire.y          = cast(s16, y)
            wire.width      = cast(u16, width)
            wire.height     = cast(u16, height)
            wire.plane_mask = Swag.U32.Max
            wire.format     = 2
            wire.segment    = .shmSegment
            let sequence = .sharedRequest(&wire, #sizeof(wire), 4, false, true)
            let wait = cast(Linux.xcb_wait_for_reply_fn, unwrap Linux.dlsym(library, "xcb_wait_for_reply".buffer))
            let sharedReply = wait(connection, sequence, null)
            var replySize: u32
            if sharedReply do
                Memory.copy(&replySize, &sharedReply.pad0[0], #sizeof(replySize))
            if sharedReply and
               sharedReply.depth == .screen.root_depth and
               sharedReply.visual == .screen.root_visual and
               replySize <= .shmSize
            {
                sharedSize = replySize
                captured   = sharedReply
            }
            else
            {
                Linux.free(sharedReply)
                .disableSharedMemory()
                shared = false
            }
        }
        if not shared do
            captured = reply(connection,
                             get(connection, 2, .screen.root, cast(s16, x), cast(s16, y), cast(u16, width), cast(u16, height), Swag.U32.Max),
                             null)
        if not captured do
            fail Swag.SystemError{"X11 cannot read the requested desktop pixels"}
        defer Linux.free(captured)
        var format: Linux.xcb_format_t
        var fi = formats(unwrap .setup)
        while fi.rem > 0 and fi.data
        {
            if fi.data.depth == captured.depth
            {
                format = fi.data[]
                break
            }

            formatNext(&fi)
        }

        var visual: Linux.xcb_visualtype_t
        var di = depths(unwrap .screenPointer)
        while di.rem > 0 and di.data
        {
            var vi = visuals(di.data)
            while vi.rem > 0 and vi.data
            {
                if vi.data.visual_id == captured.visual do
                    visual = vi.data[]
                visualNext(&vi)
            }

            depthNext(&di)
        }

        if visual._class != 4 or
           not visual.red_mask or
           not visual.green_mask or
           not visual.blue_mask or
           (format.bits_per_pixel != 16 and format.bits_per_pixel != 24 and format.bits_per_pixel != 32) or
           (format.scanline_pad != 8 and format.scanline_pad != 16 and format.scanline_pad != 32) do
            fail Errors.UnsupportedFormatError{"desktop capture needs a 16-, 24- or 32-bit X11 TrueColor visual"}
        let rowBits = cast(u64, width) * format.bits_per_pixel
        let stride  = ((rowBits + format.scanline_pad - 1) / format.scanline_pad) * (format.scanline_pad / 8)
        let count = shared ? cast(s64, sharedSize) : cast(s64, dataLength(captured))
        if count < 0 or cast(u64, count) < stride * cast(u64, height) do
            fail Swag.SystemError{"X11 returned an incomplete desktop image"}

        func channel(pixel, mask: u32)->u8
        {
            var shifted = pixel & mask
            var maximum = mask
            while maximum & 1 == 0
            {
                maximum >>= 1
                shifted >>= 1
            }

            return cast(u8, (cast(u64, shifted) * 255 + maximum / 2) / maximum)
        }

        if target.width != width or target.height != height or target.pixelFormat != .BGRA8 do
            target[] = Image.create(width, height, .BGRA8)
        let source = shared ? cast([*] u8, unwrap .shmData) : data(captured)
        let bytes  = format.bits_per_pixel / 8
        let imageHeight = cast(u64, height)
        let imageWidth  = cast(u64, width)

        // A little-endian 32-bit TrueColor reply already stores B, G and R in BGRA order.
        // Reverse its rows and make alpha opaque without per-pixel mask scaling.
        if format.bits_per_pixel == 32 and .setup.image_byte_order == 0 and
           visual.blue_mask == 0x000000FF and
           visual.green_mask == 0x0000FF00 and
           visual.red_mask == 0x00FF0000
        {
            let opaque = Math.Simd.splat(0xFF000000'u32)
            let outputBase = target.pixels.storage()
            let outputStride = cast(u64, target.rowStride)
            if imageWidth >= 3840 and imageHeight >= 2160
            {
                // Each band reads and writes disjoint rows of the shared image.
                const Bands = 8'u64
                parallel for |source, outputBase, stride, outputStride, imageHeight, imageWidth, opaque| band in Bands
                {
                    let first = band * imageHeight / Bands
                    let last  = (band + 1) * imageHeight / Bands
                    for row in first until last do
                        copyX11BgraRow(source + row * stride,
                                       outputBase + (imageHeight - row - 1) * outputStride,
                                       imageWidth, opaque)
                }
            }
            else
            {
                for row in imageHeight do
                    copyX11BgraRow(source + row * stride,
                                   outputBase + (imageHeight - row - 1) * outputStride,
                                   imageWidth, opaque)
            }
            if drawCursor do
                try .drawCursor(target, x, y)
            return
        }

        for row in cast(u64, height)
        {
            for column in cast(u64, width)
            {
                let offset = row * stride + column * bytes
                var pixel: u32
                for component in cast(u32, bytes)
                {
                    let shift = .setup.image_byte_order == 0 ? component * 8 : (bytes - component - 1) * 8
                    pixel |= cast(u32, source[offset + component]) << shift
                }

                let destination = (cast(u64, height) - row - 1) * cast(u64, target.rowStride) + column * 4
                target.pixels[destination]     = channel(pixel, visual.blue_mask)
                target.pixels[destination + 1] = channel(pixel, visual.green_mask)
                target.pixels[destination + 2] = channel(pixel, visual.red_mask)
                target.pixels[destination + 3] = 255
            }
        }

        if drawCursor do
            try .drawCursor(target, x, y)
    }

    private mtd drawCursor(image: *Image, x, y: s32) fail
    {
        let connection = unwrap .connection
        let library    = unwrap .library
        let extension  = try symbol'Linux.xcb_get_extension_data_fn(library, "xcb_get_extension_data")
        let wait       = try symbol'Linux.xcb_wait_for_reply_fn(library, "xcb_wait_for_reply")
        if not .fixesReady
        {
            let available = extension(connection, &.fixesExtension)
            if not available or not available.present do
                fail Swag.SystemError{"cursor capture needs the XFixes display extension"}
            var wire: XfixesVersionRequest
            wire.major = 4
            wire.minor = 0
            var error: *Linux.xcb_generic_error_t?
            let sequence = .extensionRequest(&.fixesExtension, &wire, #sizeof(wire), 0, false, true)
            let raw = wait(connection, sequence, &error)
            defer Linux.free(error)
            if error or not raw do
                fail Swag.SystemError{"cursor capture cannot negotiate XFixes"}
            defer Linux.free(raw)
            let negotiated = cast(*Linux.xcb_xfixes_query_version_reply_t, cast(*void, raw))
            if negotiated.major_version < 2 do
                fail Swag.SystemError{"XFixes cursor capture requires version 2"}
            .fixesReady = true
        }
        var wire: XfixesCursorRequest
        var error: *Linux.xcb_generic_error_t?
        let sequence = .extensionRequest(&.fixesExtension, &wire, #sizeof(wire), 4, false, true)
        let raw = wait(connection, sequence, &error)
        defer Linux.free(error)
        if error or not raw do
            fail Swag.SystemError{"X11 cannot read the cursor image"}
        defer Linux.free(raw)
        let cursor = cast(*Linux.xcb_xfixes_get_cursor_image_reply_t, cast(*void, raw))
        if cast(u64, cursor.length) < cast(u64, cursor.width) * cursor.height do
            fail Swag.SystemError{"X11 returned an incomplete cursor image"}
        let source = cast([*] u32, cast([*] u8, cursor) + #sizeof(Linux.xcb_xfixes_get_cursor_image_reply_t))
        for row in cast(u32, cursor.height)
        {
            let targetY = cast(s32, cursor.y) - cursor.yhot - y + cast(s32, row)
            if targetY < 0 or targetY >= image.height do
                continue
            for column in cast(u32, cursor.width)
            {
                let targetX = cast(s32, cursor.x) - cursor.xhot - x + cast(s32, column)
                if targetX < 0 or targetX >= image.width do
                    continue
                let pixel  = source[row * cursor.width + column]
                let alpha  = pixel >> 24
                let offset = cast(u64, image.height - targetY - 1) * cast(u64, image.rowStride) + cast(u64, targetX) * 4

                // XFixes returns premultiplied ARGB; the captured desktop is opaque BGRA.
                for component in 3'u32
                {
                    let value      = (pixel >> (component * 8)) & 255
                    let background = image.pixels[offset + component]
                    image.pixels[offset + component] = cast(u8, Math.min(255'u32, value + (background * (255 - alpha) + 127) / 255))
                }
            }
        }
    }
}

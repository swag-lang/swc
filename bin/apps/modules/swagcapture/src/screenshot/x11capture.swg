#global if #os == Swag.TargetOs.Linux

using Core, Pixel

// Owns an independent X11 connection for desktop capture and best-effort window queries.
// The GUI event queue remains owned by Gui; capture never consumes its events.
#[Swag.NoCopy]
struct X11Capture
{
    library:              *void?
    fixesLibrary:         *void?
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
        if .connection do
            .disconnect(.connection)
        if .fixesLibrary do
            discard Linux.dlclose(.fixesLibrary)
        if .library do
            discard Linux.dlclose(.library)
    }

    mtd atom(name: string)->u32
    {
        let connection = unwrap .connection
        let reply      = .internReply(connection, .intern(connection, 1, cast(u16, name.count), name.buffer), null)
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
        let captured   = reply(connection,
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
        let count   = dataLength(captured)
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

        var result = Image.create(width, height, .BGRA8)
        let source = data(captured)
        let bytes  = format.bits_per_pixel / 8
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

                let destination = (cast(u64, height) - row - 1) * cast(u64, result.rowStride) + column * 4
                result.pixels[destination]     = channel(pixel, visual.blue_mask)
                result.pixels[destination + 1] = channel(pixel, visual.green_mask)
                result.pixels[destination + 2] = channel(pixel, visual.red_mask)
                result.pixels[destination + 3] = 255
            }
        }

        if drawCursor do
            try .drawCursor(&result, x, y)
        return result
    }

    private mtd drawCursor(image: *Image, x, y: s32) fail
    {
        let connection = unwrap .connection
        if not .fixesLibrary do
            .fixesLibrary = Linux.dlopen("libxcb-xfixes.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        if not .fixesLibrary do
            fail Swag.SystemError{"cursor capture cannot load libxcb-xfixes.so.0"}
        let library       = .fixesLibrary
        let extension     = Linux.dlsym(library, "xcb_xfixes_id".buffer)
        let extensionData = try symbol'Linux.xcb_get_extension_data_fn(unwrap .library, "xcb_get_extension_data")
        if not extension do
            fail Swag.SystemError{"cursor capture cannot resolve the XFixes extension"}
        let available = extensionData(connection, cast(*Linux.xcb_extension_t, extension))
        if not available or not available.present do
            fail Swag.SystemError{"cursor capture needs the XFixes display extension"}
        let version      = try symbol'Linux.xcb_xfixes_query_version_fn(library, "xcb_xfixes_query_version")
        let versionReply = try symbol'Linux.xcb_xfixes_query_version_reply_fn(library, "xcb_xfixes_query_version_reply")
        let negotiated   = versionReply(connection, version(connection, 4, 0), null)
        if not negotiated do
            fail Swag.SystemError{"cursor capture cannot negotiate XFixes"}
        defer Linux.free(negotiated)
        let get    = try symbol'Linux.xcb_xfixes_get_cursor_image_fn(library, "xcb_xfixes_get_cursor_image")
        let reply  = try symbol'Linux.xcb_xfixes_get_cursor_image_reply_fn(library, "xcb_xfixes_get_cursor_image_reply")
        let pixels = try symbol'Linux.xcb_xfixes_get_cursor_image_cursor_image_fn(library, "xcb_xfixes_get_cursor_image_cursor_image")
        let length = try symbol'Linux.xcb_xfixes_get_cursor_image_cursor_image_length_fn(library, "xcb_xfixes_get_cursor_image_cursor_image_length")
        let cursor = reply(connection, get(connection), null)
        if not cursor do
            fail Swag.SystemError{"X11 cannot read the cursor image"}
        defer Linux.free(cursor)
        let pixelCount = length(cursor)
        if pixelCount < 0 or cast(u64, pixelCount) < cast(u64, cursor.width) * cursor.height do
            fail Swag.SystemError{"X11 returned an incomplete cursor image"}
        let source = pixels(cursor)
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

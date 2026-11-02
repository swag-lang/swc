#global if #os == Swag.TargetOs.Linux

using Core, Pixel

namespace LinuxSelection
{
    const MaxBytes   = 64 * 1024 * 1024'u64
    const ChunkBytes = 64 * 1024'u64
    const TimeoutMs  = 3000'u64

    struct Payload
    {
        selection: u32
        target:    u32
        type:      u32
        format:    u8 = 8
        bytes:     Array'u8
        deferred:  bool
    }

    struct Transfer
    {
        requestor: u32
        property:  u32
        target:    u32
        type:      u32
        format:    u8 = 8
        offset:    u64
        deadline:  u64
        bytes:     Array'u8
    }

    struct Value
    {
        bytes:  Array'u8
        type:   u32
        format: u8
        valid:  bool
    }

    struct Service
    {
        library:                                   *void?
        connection:                                *void?
        window:                                    u32
        root:                                      u32
        targets:                                   u32
        incr:                                      u32
        property:                                  u32
        clipboard:                                 u32
        allocator:                                 IAllocator?
        thread:                                    Threading.Thread
        payloads:                                  Array'Payload
        transfers:                                 Array'Transfer
        requests:                                  Array'Linux.xcb_selection_request_event_t
        clientMessages:                            Array'Linux.xcb_client_message_event_t
        late xcb_connect:                          Linux.xcb_connect_fn
        late xcb_disconnect:                       Linux.xcb_disconnect_fn
        late xcb_connection_has_error:             Linux.xcb_connection_has_error_fn
        late xcb_get_setup:                        Linux.xcb_get_setup_fn
        late xcb_setup_roots_iterator:             Linux.xcb_setup_roots_iterator_fn
        late xcb_screen_next:                      Linux.xcb_screen_next_fn
        late xcb_generate_id:                      Linux.xcb_generate_id_fn
        late xcb_request_check:                    Linux.xcb_request_check_fn
        late xcb_flush:                            Linux.xcb_flush_fn
        late xcb_poll_for_event:                   Linux.xcb_poll_for_event_fn
        late xcb_create_window_checked:            Linux.xcb_create_window_checked_fn
        late xcb_destroy_window_checked:           Linux.xcb_destroy_window_checked_fn
        late xcb_change_window_attributes_checked: Linux.xcb_change_window_attributes_checked_fn
        late xcb_change_property_checked:          Linux.xcb_change_property_checked_fn
        late xcb_intern_atom:                      Linux.xcb_intern_atom_fn
        late xcb_intern_atom_reply:                Linux.xcb_intern_atom_reply_fn
        late xcb_get_property:                     Linux.xcb_get_property_fn
        late xcb_get_property_reply:               Linux.xcb_get_property_reply_fn
        late xcb_get_property_value:               Linux.xcb_get_property_value_fn
        late xcb_get_property_value_length:        Linux.xcb_get_property_value_length_fn
        late xcb_send_event_checked:               Linux.xcb_send_event_checked_fn
        late xcb_set_selection_owner_checked:      Linux.xcb_set_selection_owner_checked_fn
        late xcb_get_selection_owner:              Linux.xcb_get_selection_owner_fn
        late xcb_get_selection_owner_reply:        Linux.xcb_get_selection_owner_reply_fn
        late xcb_convert_selection_checked:        Linux.xcb_convert_selection_checked_fn
        late xcb_delete_property_checked:          Linux.xcb_delete_property_checked_fn
        late xcb_get_file_descriptor:              Linux.xcb_get_file_descriptor_fn
    }

    var service: Service
    var mutex:   Swag.Mutex
    private var stopping: bool

    private func(T) symbol(library: *void, name: string)->T fail
    {
        let address = Linux.dlsym(library, name.buffer)
        if not address do
            fail Swag.SystemError{"required XCB selection symbol is unavailable"}
        return cast(T, address)
    }

    func check(cookie: Linux.xcb_void_cookie_t)->bool
    {
        let error = service.xcb_request_check(unwrap service.connection, cookie)
        if error
        {
            Linux.free(error)
            return false
        }

        return service.xcb_connection_has_error(unwrap service.connection) == 0
    }

    func atom(name: string)->u32 fail
    {
        if name.count == 0 or name.count > 65535 do
            fail Errors.BadParameterError{"selection format name length is outside 1 through 65535 bytes"}
        for byte in name where byte == 0 do
            fail Errors.BadParameterError{"selection format name contains a zero byte"}
        let reply = service.xcb_intern_atom_reply(unwrap service.connection,
                                                  service.xcb_intern_atom(unwrap service.connection, 0, cast(u16, name.count), name.buffer),
                                                  null)
        if not reply do
            fail Swag.SystemError{"cannot register X11 selection format"}
        defer Linux.free(reply)
        return reply.atom
    }

    func owner(selection: u32)->u32
    {
        let reply = service.xcb_get_selection_owner_reply(unwrap service.connection,
                                                          service.xcb_get_selection_owner(unwrap service.connection, selection),
                                                          null)
        if not reply do
            return 0
        defer Linux.free(reply)
        return reply.owner
    }

    func createRequestor()->u32
    {
        let id   = service.xcb_generate_id(unwrap service.connection)
        let mask = 1 << 22'u32
        if not check(service.xcb_create_window_checked(unwrap service.connection,
                                                       0,
                                                       id,
                                                       service.root,
                                                       0,
                                                       0,
                                                       1,
                                                       1,
                                                       0,
                                                       2,
                                                       0,
                                                       1 << 11,
                                                       &mask)) do
            return 0
        return id
    }

    func find(selection, target: u32)->*Payload?
    {
        for &payload in service.payloads where payload.selection == selection and payload.target == target do
            return payload
        return null
    }

    func forget(selection: u32)
    {
        var index = service.payloads.count
        while index
        {
            index -= 1
            if service.payloads[index].selection == selection do
                service.payloads.removeAt(index)
        }
    }

    private func notify(request: Linux.xcb_selection_request_event_t, property: u32)
    {
        // SendEvent reads exactly 32 bytes; the native notification struct itself is only 24.
        var packet: [32] u8
        let reply = cast(*Linux.xcb_selection_notify_event_t, cast(*void, &packet[0]))
        reply.response_type = Linux.XCB_SELECTION_NOTIFY
        reply.time          = request.time
        reply.requestor     = request.requestor
        reply.selection     = request.selection
        reply.target        = request.target
        reply.property      = property
        discard check(service.xcb_send_event_checked(unwrap service.connection, 0, request.requestor, 0, packet))
    }

    private func serve(request: Linux.xcb_selection_request_event_t)
    {
        let property = request.property ? request.property : request.target
        if request.owner != service.window or owner(request.selection) != service.window
        {
            notify(request, 0)
            return
        }

        if request.target == service.targets
        {
            var targets: Array'u32
            targets.add(service.targets)
            for payload in service.payloads where payload.selection == request.selection do
                targets.add(payload.target)
            let ok = check(service.xcb_change_property_checked(unwrap service.connection,
                                                               0,
                                                               request.requestor,
                                                               property,
                                                               4,
                                                               32,
                                                               cast(u32, targets.count),
                                                               targets.storage()))
            notify(request, ok ? property : 0)
            return
        }

        let payload = find(request.selection, request.target)
        if not payload
        {
            notify(request, 0)
            return
        }

        if payload.deferred
        {
            if service.requests.count < 16 do
                service.requests.add(request)
            else do
                notify(request, 0)
            return
        }

        if payload.bytes.count <= ChunkBytes
        {
            let ok = check(service.xcb_change_property_checked(unwrap service.connection,
                                                               0,
                                                               request.requestor,
                                                               property,
                                                               payload.type ? payload.type : request.target,
                                                               payload.format,
                                                               cast(u32, payload.bytes.count / (payload.format / 8)),
                                                               payload.bytes.storage()))
            notify(request, ok ? property : 0)
            return
        }

        var outstanding = payload.bytes.count
        for transfer in service.transfers do
            outstanding += transfer.bytes.count
        if service.transfers.count >= 16 or outstanding > MaxBytes
        {
            notify(request, 0)
            return
        }

        let mask = 1 << 22'u32
        if not check(service.xcb_change_window_attributes_checked(unwrap service.connection, request.requestor, 1 << 11, &mask))
        {
            notify(request, 0)
            return
        }

        with var transfer: Transfer
        {
            .requestor       = request.requestor
            .property        = property
            .target          = request.target
            .type            = payload.type ? payload.type : request.target
            .format          = payload.format
            .deadline        = Time.monotonicMilliseconds() + TimeoutMs
            .bytes.allocator = service.allocator
            .bytes.add(payload.bytes.toSlice())
        }

        let count = cast(u32, transfer.bytes.count)
        let ok    = check(service.xcb_change_property_checked(unwrap service.connection,
                                                              0,
                                                              request.requestor,
                                                              property,
                                                              service.incr,
                                                              32,
                                                              1,
                                                              &count))
        if ok do
            service.transfers.add(#move transfer)
        notify(request, ok ? property : 0)
    }

    private func advance(property: Linux.xcb_property_notify_event_t)
    {
        if property.state != Linux.XCB_PROPERTY_DELETE do
            return
        for index in service.transfers.count
        {
            let transfer = &service.transfers[index]
            if transfer.requestor != property.window or transfer.property != property.atom do
                continue
            let count = Math.min(ChunkBytes, transfer.bytes.count - transfer.offset)
            let bytes = transfer.bytes.toSlice()[transfer.offset until transfer.offset + count]
            let ok    = check(service.xcb_change_property_checked(unwrap service.connection, 0, transfer.requestor, transfer.property, transfer.type, transfer.format, cast(u32, count / (transfer.format / 8)), bytes.buffer))
            transfer.offset   += count
            transfer.deadline = Time.monotonicMilliseconds() + TimeoutMs
            if not ok or count == 0 do
                service.transfers.removeAt(index)
            return
        }
    }

    func dispatch(event: *Linux.xcb_generic_event_t)
    {
        switch event.response_type & 0x7F
        {
        case Linux.XCB_CLIENT_MESSAGE:
            if service.clientMessages.count < 64 do
                service.clientMessages.add(cast(*Linux.xcb_client_message_event_t, cast(*void, event))[])

        case Linux.XCB_SELECTION_REQUEST:
            serve(cast(*Linux.xcb_selection_request_event_t, cast(*void, event))[])

        case Linux.XCB_SELECTION_CLEAR:
            let cleared = cast(*Linux.xcb_selection_clear_event_t, cast(*void, event))
            if cleared.owner == service.window and owner(cleared.selection) != service.window do
                forget(cleared.selection)

        case Linux.XCB_PROPERTY_NOTIFY:
            advance(cast(*Linux.xcb_property_notify_event_t, cast(*void, event))[])
        }
    }

    private func serviceThread(thread: const *Threading.Thread)
    {
        while not thread.requestEnd.isRaised()
        {
            mutex.lock()
            for 128
            {
                let event = service.xcb_poll_for_event(unwrap service.connection)
                if not event do
                    break
                dispatch(event)
                Linux.free(event)
            }

            var index = service.transfers.count
            while index
            {
                index -= 1
                if service.transfers[index].deadline <= Time.monotonicMilliseconds() do
                    service.transfers.removeAt(index)
            }

            let disconnected = service.xcb_connection_has_error(unwrap service.connection) != 0
            let fd = service.xcb_get_file_descriptor(unwrap service.connection)
            mutex.unlock()
            if disconnected do
                break
            var poll: Linux.pollfd = {fd: fd, events: Linux.POLLIN}
            discard Linux.poll(&poll, 1, 100)
        }
    }

    func ensure() fail
    {
        if stopping do
            fail Swag.SystemError{"selection services have shut down"}
        if service.connection
        {
            if service.xcb_connection_has_error(unwrap service.connection) != 0 do
                fail Swag.SystemError{"X11 selection connection was lost"}
            return
        }

        let loaded = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        if not loaded do
            fail Swag.SystemError{"cannot load XCB selection services"}
        let library: *void = loaded
        defer #fail discard Linux.dlclose(library)
        service.xcb_connect                          = try symbol'Linux.xcb_connect_fn(library, "xcb_connect")
        service.xcb_disconnect                       = try symbol'Linux.xcb_disconnect_fn(library, "xcb_disconnect")
        service.xcb_connection_has_error             = try symbol'Linux.xcb_connection_has_error_fn(library, "xcb_connection_has_error")
        service.xcb_get_setup                        = try symbol'Linux.xcb_get_setup_fn(library, "xcb_get_setup")
        service.xcb_setup_roots_iterator             = try symbol'Linux.xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
        service.xcb_screen_next                      = try symbol'Linux.xcb_screen_next_fn(library, "xcb_screen_next")
        service.xcb_generate_id                      = try symbol'Linux.xcb_generate_id_fn(library, "xcb_generate_id")
        service.xcb_request_check                    = try symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
        service.xcb_flush                            = try symbol'Linux.xcb_flush_fn(library, "xcb_flush")
        service.xcb_poll_for_event                   = try symbol'Linux.xcb_poll_for_event_fn(library, "xcb_poll_for_event")
        service.xcb_create_window_checked            = try symbol'Linux.xcb_create_window_checked_fn(library, "xcb_create_window_checked")
        service.xcb_destroy_window_checked           = try symbol'Linux.xcb_destroy_window_checked_fn(library, "xcb_destroy_window_checked")
        service.xcb_change_window_attributes_checked = try symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
        service.xcb_change_property_checked          = try symbol'Linux.xcb_change_property_checked_fn(library, "xcb_change_property_checked")
        service.xcb_intern_atom                      = try symbol'Linux.xcb_intern_atom_fn(library, "xcb_intern_atom")
        service.xcb_intern_atom_reply                = try symbol'Linux.xcb_intern_atom_reply_fn(library, "xcb_intern_atom_reply")
        service.xcb_get_property                     = try symbol'Linux.xcb_get_property_fn(library, "xcb_get_property")
        service.xcb_get_property_reply               = try symbol'Linux.xcb_get_property_reply_fn(library, "xcb_get_property_reply")
        service.xcb_get_property_value               = try symbol'Linux.xcb_get_property_value_fn(library, "xcb_get_property_value")
        service.xcb_get_property_value_length        = try symbol'Linux.xcb_get_property_value_length_fn(library, "xcb_get_property_value_length")
        service.xcb_send_event_checked               = try symbol'Linux.xcb_send_event_checked_fn(library, "xcb_send_event_checked")
        service.xcb_set_selection_owner_checked      = try symbol'Linux.xcb_set_selection_owner_checked_fn(library, "xcb_set_selection_owner_checked")
        service.xcb_get_selection_owner              = try symbol'Linux.xcb_get_selection_owner_fn(library, "xcb_get_selection_owner")
        service.xcb_get_selection_owner_reply        = try symbol'Linux.xcb_get_selection_owner_reply_fn(library, "xcb_get_selection_owner_reply")
        service.xcb_convert_selection_checked        = try symbol'Linux.xcb_convert_selection_checked_fn(library, "xcb_convert_selection_checked")
        service.xcb_delete_property_checked          = try symbol'Linux.xcb_delete_property_checked_fn(library, "xcb_delete_property_checked")
        service.xcb_get_file_descriptor              = try symbol'Linux.xcb_get_file_descriptor_fn(library, "xcb_get_file_descriptor")
        var screenIndex: s32
        let connected = service.xcb_connect(null, &screenIndex)
        if not connected do
            fail Swag.SystemError{"cannot connect to the X11 selection server"}
        let connection: *void = connected
        defer #fail service.xcb_disconnect(connection)
        if service.xcb_connection_has_error(connection) != 0 do
            fail Swag.SystemError{"cannot connect to the X11 selection server"}
        var screens = service.xcb_setup_roots_iterator(service.xcb_get_setup(connection))
        for screenIndex do
            service.xcb_screen_next(&screens)
        if not screens.data do
            fail Swag.SystemError{"X11 selection screen is unavailable"}
        service.connection = connection
        defer #fail service.connection = null
        service.root      = screens.data.root
        service.targets   = try atom("TARGETS")
        service.incr      = try atom("INCR")
        service.property  = try atom("_SWAG_SELECTION_VALUE")
        service.clipboard = try atom("CLIPBOARD")
        service.window    = createRequestor()
        if not service.window do
            fail Swag.SystemError{"cannot create the X11 selection owner"}
        service.allocator = Swag.getContext().defaultAllocator orelse Swag.getContext().allocator
        service.payloads.allocator       = service.allocator
        service.transfers.allocator      = service.allocator
        service.requests.allocator       = service.allocator
        service.clientMessages.allocator = service.allocator
        try service.thread.init(&serviceThread, tempAllocSize: 0)
        service.thread.context.allocator        = service.allocator
        service.thread.context.defaultAllocator = service.allocator
        try service.thread.start()
        service.library = library
    }

    // The caller serializes all operations through mutex. Each conversion uses a fresh
    // requestor window, so a late reply from a timed-out transfer cannot satisfy a later call.
    func read(selection, target: u32, expiresAt: u64 = 0)->Value
    {
        var result: #returntype
        if owner(selection) == service.window
        {
            if target == service.targets
            {
                var targets: Array'u32
                targets.add(service.targets)
                for payload in service.payloads where payload.selection == selection do
                    targets.add(payload.target)
                result.bytes.add(Swag.makeSlice(cast(const [*]u8, targets.storage()), targets.count * 4))
                result.type   = 4
                result.format = 32
                result.valid  = true
            }
            else
            {
                let payload = find(selection, target)
                if payload
                {
                    result.bytes.add(payload.bytes.toSlice())
                    result.type   = payload.type ? payload.type : target
                    result.format = payload.format
                    result.valid  = true
                }
            }

            return result
        }

        let requestor = createRequestor()
        if not requestor do
            return result
        defer discard check(service.xcb_destroy_window_checked(unwrap service.connection, requestor))
        if not check(service.xcb_convert_selection_checked(unwrap service.connection,
                                                           requestor,
                                                           selection,
                                                           target,
                                                           service.property,
                                                           0)) do
            return result
        let localDeadline = Time.monotonicMilliseconds() + TimeoutMs
        let deadline      = expiresAt ? Math.min(expiresAt, localDeadline) : localDeadline
        var incremental   = false
        for
        {
            if Time.monotonicMilliseconds() >= deadline or service.xcb_connection_has_error(unwrap service.connection) != 0 do
                return {}
            let event = service.xcb_poll_for_event(unwrap service.connection)
            if not event
            {
                var poll: Linux.pollfd = {fd: service.xcb_get_file_descriptor(unwrap service.connection), events: Linux.POLLIN}
                discard Linux.poll(&poll, 1, 20)
                continue
            }

            defer Linux.free(event)
            let kind  = event.response_type & 0x7F
            var ready = false
            if not incremental and kind == Linux.XCB_SELECTION_NOTIFY
            {
                let reply = cast(*Linux.xcb_selection_notify_event_t, cast(*void, event))
                if reply.requestor != requestor or
                   reply.selection != selection or
                   reply.target != target do
                    continue
                if reply.property != service.property do
                    return {}
                ready = true
            }
            elif incremental and kind == Linux.XCB_PROPERTY_NOTIFY
            {
                let property = cast(*Linux.xcb_property_notify_event_t, cast(*void, event))
                ready = property.window == requestor and
                        property.atom == service.property and
                        property.state == Linux.XCB_PROPERTY_NEW_VALUE
            }

            if not ready
            {
                dispatch(event)
                continue
            }

            let reply = service.xcb_get_property_reply(unwrap service.connection,
                                                       service.xcb_get_property(unwrap service.connection,
                                                                                0,
                                                                                requestor,
                                                                                service.property,
                                                                                0,
                                                                                0,
                                                                                cast(u32, MaxBytes / 4 + 1)),
                                                       null)
            if not reply do
                return {}
            defer Linux.free(reply)
            let count = service.xcb_get_property_value_length(reply)
            if count < 0 or cast(u64, count) > MaxBytes - result.bytes.count or reply.bytes_after != 0 do
                return {}
            if not incremental and reply.type == service.incr
            {
                if reply.format != 32 or count != 4 do
                    return {}
                let expected = cast(*u32, service.xcb_get_property_value(reply))[]
                if expected > MaxBytes do
                    return {}
                incremental = true
            }
            else
            {
                if reply.type == 0 or (reply.format != 8 and reply.format != 16 and reply.format != 32) do
                    return {}
                if result.type and (result.type != reply.type or result.format != reply.format) do
                    return {}
                result.type   = reply.type
                result.format = reply.format
                if count do
                    result.bytes.add(Swag.makeSlice(cast(const [*]u8, service.xcb_get_property_value(reply)), cast(u64, count)))
                if not incremental or count == 0
                {
                    result.valid = true
                    discard check(service.xcb_delete_property_checked(unwrap service.connection, requestor, service.property))
                    return result
                }
            }

            if not check(service.xcb_delete_property_checked(unwrap service.connection, requestor, service.property)) do
                return {}
        }
    }

    func publish(selection, target: u32, bytes: const [..]u8)->bool
    {
        if bytes.count > MaxBytes do
            return false
        let previous = owner(selection)
        if previous != service.window
        {
            // Adding one format preserves an existing owner's other formats. Gather before
            // taking ownership; a changing owner or an unbounded transfer leaves it untouched.
            var inherited: Array'Payload
            inherited.allocator = service.allocator
            var total    = bytes.count
            let deadline = Time.monotonicMilliseconds() + TimeoutMs
            if previous
            {
                let targets = read(selection, service.targets, deadline)
                if not targets.valid or
                   targets.format != 32 or
                   targets.bytes.count % 4 or
                   targets.bytes.count > 2048 do
                    return false
                let atoms     = cast(const [*]u32, targets.bytes.storage())
                let multiple  = catch atom("MULTIPLE")
                let timestamp = catch atom("TIMESTAMP")
                for index in targets.bytes.count / 4
                {
                    let offered = atoms[index]
                    if offered == target or
                       offered == service.targets or
                       offered == service.incr or
                       offered == multiple or
                       offered == timestamp do
                        continue
                    if Time.monotonicMilliseconds() >= deadline do
                        return false
                    let value = read(selection, offered, deadline)
                    if not value.valid or value.bytes.count > MaxBytes - total do
                        return false
                    total += value.bytes.count
                    with var item: Payload
                    {
                        .selection       = selection
                        .target          = offered
                        .type            = value.type
                        .format          = value.format
                        .bytes.allocator = service.allocator
                        .bytes.add(value.bytes.toSlice())
                    }

                    inherited.add(#move item)
                }
            }

            if owner(selection) != previous do
                return false
            if not check(service.xcb_set_selection_owner_checked(unwrap service.connection, service.window, selection, 0)) or
               owner(selection) != service.window do
                return false
            forget(selection)
            for &item in inherited do
                service.payloads.add(#move item[])
        }

        var payload = find(selection, target)
        if not payload
        {
            service.payloads.add({selection, target})
            payload = service.payloads.backPtr()
            payload.bytes.allocator = service.allocator
        }

        payload.type     = target
        payload.deferred = false
        payload.format   = 8
        payload.bytes.clear()
        payload.bytes.add(bytes)
        return true
    }

    // Deferred formats are fulfilled by the source UI loop, never by the transport worker.
    func announce(selection, target: u32)->bool
    {
        if not publish(selection, target, "") do
            return false
        (unwrap find(selection, target)).deferred = true
        return true
    }

    func requested(selection: u32)->u32
    {
        for request in service.requests where request.selection == selection do
            return request.target
        return 0
    }

    func complete(selection, target: u32, bytes: const [..]u8)
    {
        let published = owner(selection) == service.window and publish(selection, target, bytes)
        var index     = service.requests.count
        while index
        {
            index -= 1
            let request = service.requests[index]
            if request.selection != selection or request.target != target do
                continue
            service.requests.removeAt(index)
            if published do
                serve(request)
            else do
                notify(request, 0)
        }
    }

    func release(selection: u32)
    {
        var index = service.requests.count
        while index
        {
            index -= 1
            let request = service.requests[index]
            if request.selection != selection do
                continue
            service.requests.removeAt(index)
            notify(request, 0)
        }

        forget(selection)
        if owner(selection) == service.window do
            discard check(service.xcb_set_selection_owner_checked(unwrap service.connection, 0, selection, 0))
    }

    func clear(selection: u32)
    {
        forget(selection)
        discard check(service.xcb_set_selection_owner_checked(unwrap service.connection, service.window, selection, 0))
    }

    #drop
    {
        mutex.lock()
        stopping = true
        let running = service.thread.isValid()
        if running do
            service.thread.safeForceEnd()
        mutex.unlock()
        if running do
            service.thread.wait()
        mutex.lock()
        if service.connection do
            service.xcb_disconnect(unwrap service.connection)
        service.connection = null
        if service.library do
            discard Linux.dlclose(unwrap service.library)
        service.library = null
        service.payloads.clear()
        service.transfers.clear()
        service.requests.clear()
        service.clientMessages.clear()
        mutex.unlock()
    }
}

namespace Clipboard
{
    private var g_FormatNames: Array'String

    // Returns a process-local token for a named clipboard format, registering it on first use.
    //
    // Other processes exchange the same named X11 target; numeric tokens are local to this process.
    // Registration does not open a display, so sandboxed and headless consumers can register formats.
    public func registerFormat(name: string)->ValueFormat fail
    {
        if name.count == 0 or name.count > 65535 do
            fail Errors.BadParameterError{"clipboard format name length is outside 1 through 65535 bytes"}
        for byte in name where byte == 0 do
            fail Errors.BadParameterError{"clipboard format name contains a zero byte"}
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        for index in g_FormatNames.count where g_FormatNames[index].toString() == name do
            return index + 1
        let allocator = Swag.getContext().defaultAllocator orelse Swag.getContext().allocator
        if not g_FormatNames.allocator do
            g_FormatNames.allocator = allocator
        var saved: String
        saved.allocator = g_FormatNames.allocator
        saved = name
        g_FormatNames.add(#move saved)
        return g_FormatNames.count
    }

    private func nativeFormat(format: ValueFormat)->u32 fail
    {
        if format == 0 or format > g_FormatNames.count do
            fail Errors.BadParameterError{"clipboard format is not registered"}
        return try LinuxSelection.atom(g_FormatNames[format - 1].toString())
    }

    private func hasTarget(target: u32)->bool
    {
        let targets = LinuxSelection.read(LinuxSelection.service.clipboard, LinuxSelection.service.targets)
        if not targets.valid or targets.type != 4 or targets.format != 32 or targets.bytes.count % 4 do
            return false
        let values = cast(const [*]u32, targets.bytes.storage())
        for index in targets.bytes.count / 4 where values[index] == target do
            return true
        return false
    }

    // Reports whether the clipboard offers the named registered format.
    public func hasFormat(fmt: ValueFormat)->bool
    {
        if g_Fake.enabled do
            return fakeFind(fmt) != null
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch { try LinuxSelection.ensure(); return hasTarget(try nativeFormat(fmt)) }
        return false
    }

    // Reports whether a typed payload matches `type`; a null type checks only format presence.
    public func hasTypedData(fmt: ValueFormat, type: typeinfo?)->bool
    {
        if g_Fake.enabled
        {
            let entry = fakeFind(fmt)
            return entry != null and (not type or entry.crc == type.crc)
        }

        if not type do
            return hasFormat(fmt)
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            let value = LinuxSelection.read(LinuxSelection.service.clipboard, try nativeFormat(fmt))
            if value.valid and value.format == 8 and value.type == try nativeFormat(fmt) do
                return (try TypedPayload.decode(value.bytes.toSlice())).matches(type)
        }

        return false
    }

    // Publishes a copied typed payload without clearing other formats.
    public func addTypedData(fmt: ValueFormat, type: typeinfo?, data: const [..]u8)
    {
        if g_Fake.enabled do
            return fakeAddTypedData(fmt, type, data)
        let bytes = TypedPayload{crc: type ? type.crc : 0, data: data}.encode()
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            discard LinuxSelection.publish(LinuxSelection.service.clipboard, try nativeFormat(fmt), bytes.toSlice())
        }
    }

    // Returns a copied matching typed payload, or an empty array when the transfer fails or does not match.
    public func getTypedData(fmt: ValueFormat, type: typeinfo?)->Array'u8
    {
        if g_Fake.enabled do
            return fakeGetTypedData(fmt, type)
        var result: #returntype
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            let value = LinuxSelection.read(LinuxSelection.service.clipboard, try nativeFormat(fmt))
            if value.valid and value.format == 8 and value.type == try nativeFormat(fmt)
            {
                let payload = try TypedPayload.decode(value.bytes.toSlice())
                if payload.matches(type) and payload.data do
                    result.add(payload.data)
            }
        }

        return result
    }

    // Reports whether the clipboard offers a PNG image without decoding it.
    public func hasImage()->bool
    {
        if g_Fake.enabled do
            return g_Fake.hasImg
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch { try LinuxSelection.ensure(); return hasTarget(try LinuxSelection.atom("image/png")) }
        return false
    }

    // Replaces the clipboard with a PNG copy of `image`; an invalid or unencodable image leaves it empty.
    public func addImage(image: Image)
    {
        if g_Fake.enabled
        {
            fakeClear()
            if image.isValid()
            {
                g_Fake.hasImg = true
                g_Fake.img    = Image.create(image.width, image.height, image.pixelFormat, image.pixels.toSlice(), image.alphaMode)
            }

            return
        }

        clear()
        if not image.isValid() do
            return
        catch
        {
            let bytes = try image.encodeToBytes("clipboard.png", Png.EncodeOptions{compressionLevel: .BestSpeed})
            LinuxSelection.mutex.lock()
            defer LinuxSelection.mutex.unlock()
            try LinuxSelection.ensure()
            discard LinuxSelection.publish(LinuxSelection.service.clipboard, try LinuxSelection.atom("image/png"), bytes.toSlice())
        }
    }

    // Returns a decoded PNG copy, or an invalid image when no bounded transfer can be decoded.
    public func getImage()->Image
    {
        if g_Fake.enabled do
            return g_Fake.hasImg ? g_Fake.img : Image{}
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            let value = LinuxSelection.read(LinuxSelection.service.clipboard, try LinuxSelection.atom("image/png"))
            if value.valid and value.format == 8 and value.type == try LinuxSelection.atom("image/png") do
                return try Image.decode("clipboard.png", value.bytes.toSlice(), {})
        }

        return {}
    }

    // Reports whether the clipboard offers UTF-8 or Latin-1 text.
    public func hasString()->bool
    {
        if g_Fake.enabled do
            return g_Fake.hasStr
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            return hasTarget(try LinuxSelection.atom("UTF8_STRING")) or hasTarget(31)
        }

        return false
    }

    // Publishes UTF-8 text without clearing other formats.
    public func addString(str: string) { writeString(str, false) }

    // Replaces every clipboard format with UTF-8 text.
    public func setString(str: string) { writeString(str, true) }

    private func writeString(str: string, replace: bool)
    {
        if g_Fake.enabled
        {
            if replace do
                fakeClear()
            g_Fake.hasStr = true
            g_Fake.str    = str
            return
        }

        if not Utf8.isValid(str) or str.count > LinuxSelection.MaxBytes do
            return
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            if replace do
                LinuxSelection.clear(LinuxSelection.service.clipboard)
            discard LinuxSelection.publish(LinuxSelection.service.clipboard, try LinuxSelection.atom("UTF8_STRING"), str)
            discard LinuxSelection.publish(LinuxSelection.service.clipboard, try LinuxSelection.atom("text/plain;charset=utf-8"), str)
        }
    }

    // Returns UTF-8 text, or an empty string when no valid bounded transfer is available.
    //
    // UTF8_STRING is preferred; legacy STRING data is converted from Latin-1. Native transfers
    // are bounded to 64 MiB and three seconds. The process serves its clipboard while it remains alive.
    public func getString()->String
    {
        if g_Fake.enabled do
            return g_Fake.hasStr ? g_Fake.str : String{}
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            let utf8 = try LinuxSelection.atom("UTF8_STRING")
            for target in [utf8, 31'u32]
            {
                let value = LinuxSelection.read(LinuxSelection.service.clipboard, target)
                if not value.valid or value.format != 8 or value.type != target do
                    continue
                if target == utf8
                {
                    if Utf8.isValid(value.bytes.toSlice()) do
                        return String.from(cast(string, value.bytes.toSlice()))
                    return {}
                }

                var result: String
                for byte in value.bytes.toSlice() do
                    result += cast(rune, byte)
                return result
            }
        }

        return {}
    }

    // Removes every offered clipboard format and takes ownership of the empty selection.
    public func clear()
    {
        if g_Fake.enabled do
            return fakeClear()
        LinuxSelection.mutex.lock()
        defer LinuxSelection.mutex.unlock()
        catch
        {
            try LinuxSelection.ensure()
            LinuxSelection.clear(LinuxSelection.service.clipboard)
        }
    }
}

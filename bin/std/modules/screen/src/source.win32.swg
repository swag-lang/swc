#global if #os == Swag.TargetOs.Windows

using Core, Core.Errors, Pixel, Win32

private const MaxSplitRects = 8'u32

#[Swag.Inline]
internal func copyMappedBgraRows(destinationBottomRow: [*] u8, destinationStride: u64,
                                 sourceTopRow: const [*] u8, sourceStride: u64,
                                 rowBytes: u64, rowCount: u64)
{
    if rowBytes * rowCount < 8 * 1_048_576
    {
        for row in rowCount do
            Memory.copy(destinationBottomRow - row * destinationStride,
                        sourceTopRow + row * sourceStride, rowBytes)
        return
    }

    let rowsPerChunk = Math.max(1'u64, 1_048_576 / rowBytes)
    let chunkCount = (rowCount + rowsPerChunk - 1) / rowsPerChunk
    parallel for |destinationBottomRow, destinationStride, sourceTopRow,
                  sourceStride, rowBytes, rowCount, rowsPerChunk| chunk in chunkCount
    {
        let first = chunk * rowsPerChunk
        let last = Math.min(rowCount, first + rowsPerChunk)
        for row in first until last do
            Memory.copy(destinationBottomRow - row * destinationStride,
                        sourceTopRow + row * sourceStride, rowBytes)
    }
}

private struct ChangedBounds
{
    known:   bool
    changed: bool
    bounds:  RECT
    rectCount: u32
    copiedPixels: u64
}

// One DXGI duplication and a staging texture for an area on a single output.
#[Swag.NoCopy]
struct NativeSource
{
    options:      SourceOptions
    device:       *ID3D11Device?
    context:      *ID3D11DeviceContext?
    adapter:      *IDXGIAdapter?
    output:       *IDXGIOutput?
    output1:      *IDXGIOutput1?
    duplication:  *IDXGIOutputDuplication?
    staging:      *ID3D11Texture2D?
    outputBounds: RECT
    hasLast:      bool
    dirtyRects:   Array'RECT
    moveRects:    Array'DXGI_OUTDUPL_MOVE_RECT
    changedRects: Array'RECT
    updatedBounds: RECT
    pendingResource:           *IDXGIResource?
    pendingTexture:            *ID3D11Texture2D?
    pendingLeft:               u32
    pendingTop:                u32
    pendingRight:              u32
    pendingBottom:             u32
    pendingSubmitMicroseconds: u64
    pendingMultiRect:          bool
    pending:                   bool
    metrics:      SourceMetrics
}

impl NativeSource
{
    mtd abortGrab()
    {
        if not .pending do
            return
        release(.pendingTexture)
        release(.pendingResource)
        let duplication = unwrap .duplication
        discard duplication.lpVtbl.ReleaseFrame(duplication)
        .pendingTexture  = null
        .pendingResource = null
        .pending         = false
    }

    mtd flushReadback()
    {
        if .pending
        {
            let context = unwrap .context
            let start = Time.monotonicMicroseconds()
            context.lpVtbl.Flush(context)
            .pendingSubmitMicroseconds += Time.monotonicMicroseconds() - start
        }
    }

    private mtd includeChangedRect(changed: *ChangedBounds, rect: RECT, captureX, captureY: s32)
    {
        let left = Math.max(rect.left, captureX)
        let top = Math.max(rect.top, captureY)
        let right = Math.min(rect.right, captureX + .options.width)
        let bottom = Math.min(rect.bottom, captureY + .options.height)
        if right <= left or bottom <= top do
            return
        changed.rectCount += 1
        if changed.rectCount <= MaxSplitRects
        {
            .changedRects.add(RECT{left - captureX, top - captureY,
                                   right - captureX, bottom - captureY})
            changed.copiedPixels += cast(u64, right - left) * cast(u64, bottom - top)
        }
        if not changed.changed
        {
            changed.bounds = RECT{left - captureX, top - captureY,
                                  right - captureX, bottom - captureY}
            changed.changed = true
        }
        else
        {
            changed.bounds.left = Math.min(changed.bounds.left, left - captureX)
            changed.bounds.top = Math.min(changed.bounds.top, top - captureY)
            changed.bounds.right = Math.max(changed.bounds.right, right - captureX)
            changed.bounds.bottom = Math.max(changed.bounds.bottom, bottom - captureY)
        }
    }

    // The acquired texture already contains moved pixels at their destination. Treat both
    // destination and dirty rectangles as regions to read from that final texture.
    private mtd changedBounds(duplication: *IDXGIOutputDuplication, metadataSize: u32,
                              captureX, captureY: s32)->ChangedBounds
    {
        var result: #returntype
        .changedRects.clear()
        if not metadataSize or metadataSize > 1_048_576 do
            return result
        .dirtyRects.resize(cast(u64, metadataSize) / #sizeof(RECT) + 1)
        .moveRects.resize(cast(u64, metadataSize) / #sizeof(DXGI_OUTDUPL_MOVE_RECT) + 1)
        var used: u32
        let moves = duplication.lpVtbl.GetFrameMoveRects(duplication,
                        cast(u32, .moveRects.count * #sizeof(DXGI_OUTDUPL_MOVE_RECT)),
                        &.moveRects[0], &used)
        if moves < 0 or used % #sizeof(DXGI_OUTDUPL_MOVE_RECT) do
            return result
        for index in cast(u64, used / #sizeof(DXGI_OUTDUPL_MOVE_RECT)) do
            .includeChangedRect(&result, .moveRects[index].DestinationRect, captureX, captureY)

        used = 0
        let dirty = duplication.lpVtbl.GetFrameDirtyRects(duplication,
                        cast(u32, .dirtyRects.count * #sizeof(RECT)),
                        &.dirtyRects[0], &used)
        if dirty < 0 or used % #sizeof(RECT) do
            return ChangedBounds{}
        for index in cast(u64, used / #sizeof(RECT)) do
            .includeChangedRect(&result, .dirtyRects[index], captureX, captureY)
        result.known = true
        return result
    }

    private func release(raw: *void?)
    {
        if raw
        {
            let unknown = cast(*IUnknown, raw)
            discard unknown.lpVtbl.Release(unknown)
        }
    }

    func open(options: SourceOptions, shared: *NativeSource? = null)->NativeSource fail
    {
        if options.includeCursor do
            fail UnsupportedFormatError{"DXGI screen capture does not include a separate pointer yet"}
        var result: #returntype
        result.options = options
        if let existing = shared
        {
            result.device = existing.device
            result.context = existing.context
            result.adapter = existing.adapter
            let deviceRef = cast(*IUnknown, cast(*void, unwrap result.device))
            let contextRef = cast(*IUnknown, cast(*void, unwrap result.context))
            let adapterRef = cast(*IUnknown, cast(*void, unwrap result.adapter))
            discard deviceRef.lpVtbl.AddRef(deviceRef)
            discard contextRef.lpVtbl.AddRef(contextRef)
            discard adapterRef.lpVtbl.AddRef(adapterRef)
        }
        else
        {
            let hr = D3D11CreateDevice(null, D3D_DRIVER_TYPE_HARDWARE, null,
                                       D3D11_CREATE_DEVICE_BGRA_SUPPORT, null, 0,
                                       D3D11_SDK_VERSION, &result.device, null, &result.context)
            if hr < 0 do
                fail SystemError{"cannot create screen capture graphics device", errorID: cast(u64, cast #bit (u32, hr))}
            let device = unwrap result.device
            let deviceUnknown = cast(*IUnknown, cast(*void, device))
            var rawDevice: LPVOID
            let deviceId = IID_IDXGIDevice
            var statusDevice = deviceUnknown.lpVtbl.QueryInterface(deviceUnknown, &deviceId, &rawDevice)
            if statusDevice < 0 do
                fail SystemError{"cannot query screen capture display device", errorID: cast(u64, cast #bit (u32, statusDevice))}
            let displayDevice = cast(*IDXGIDevice, unwrap rawDevice)
            defer release(displayDevice)
            statusDevice = displayDevice.lpVtbl.GetAdapter(displayDevice, &result.adapter)
            if statusDevice < 0 do
                fail SystemError{"cannot find screen capture display adapter", errorID: cast(u64, cast #bit (u32, statusDevice))}
        }
        let device = unwrap result.device
        let unknown = cast(*IUnknown, cast(*void, device))
        var raw: LPVOID
        let adapter = unwrap result.adapter
        var status: HRESULT
        let right  = cast(s64, options.x) + options.width
        let bottom = cast(s64, options.y) + options.height
        var index: u32
        var found = false
        while not found
        {
            var candidate: *IDXGIOutput?
            status = adapter.lpVtbl.EnumOutputs(adapter, index, &candidate)
            if status == DXGI_ERROR_NOT_FOUND do
                break
            if status < 0 do
                fail SystemError{"cannot enumerate screen capture outputs", errorID: cast(u64, cast #bit (u32, status))}
            let output = unwrap candidate
            var desc: DXGI_OUTPUT_DESC
            status = output.lpVtbl.GetDesc(output, &desc)
            if status < 0
            {
                release(output)
                fail SystemError{"cannot read screen capture output geometry", errorID: cast(u64, cast #bit (u32, status))}
            }
            if desc.AttachedToDesktop and desc.Rotation == 1 and
               options.x >= desc.DesktopCoordinates.left and options.y >= desc.DesktopCoordinates.top and
               right <= desc.DesktopCoordinates.right and bottom <= desc.DesktopCoordinates.bottom
            {
                result.output       = output
                result.outputBounds = desc.DesktopCoordinates
                found = true
            }
            else do
                release(output)
            index += 1
        }
        if not found do
            fail UnsupportedFormatError{"screen capture area is not inside one unrotated display"}

        let output = unwrap result.output
        raw = null
        let outputId = IID_IDXGIOutput1
        let outputUnknown = cast(*IUnknown, cast(*void, output))
        status = outputUnknown.lpVtbl.QueryInterface(outputUnknown, &outputId, &raw)
        if status < 0 do
            fail SystemError{"cannot query desktop duplication output", errorID: cast(u64, cast #bit (u32, status))}
        result.output1 = cast(*IDXGIOutput1, unwrap raw)
        let output1 = result.output1
        status = output1.lpVtbl.DuplicateOutput(output1, unknown, &result.duplication)
        if status < 0 do
            fail SystemError{"cannot duplicate desktop output", errorID: cast(u64, cast #bit (u32, status))}

        let textureDesc = D3D11_TEXTURE2D_DESC{
            cast(u32, options.width), cast(u32, options.height), 1, 1,
            DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC{1, 0},
            D3D11_USAGE_STAGING, 0, D3D11_CPU_ACCESS_READ, 0}
        status = device.lpVtbl.CreateTexture2D(device, &textureDesc, null, &result.staging)
        if status < 0 do
            fail SystemError{"cannot create screen capture readback texture", errorID: cast(u64, cast #bit (u32, status))}
        return result
    }

    // Starts GPU readback without waiting for the mapped pixels.
    mtd beginGrab()->bool fail
    {
        Swag.assert(not .pending)
        .updatedBounds = RECT{}
        .pendingMultiRect = false
        if not .duplication do
            fail SystemError{"screen capture output was lost"}
        let duplication = .duplication
        var info: DXGI_OUTDUPL_FRAME_INFO
        var resource: *IDXGIResource?
        let acquireStart = Time.monotonicMicroseconds()
        let status = duplication.lpVtbl.AcquireNextFrame(duplication, .hasLast ? 0 : 1000,
                                                          &info, &resource)
        let acquireDuration = Time.monotonicMicroseconds() - acquireStart
        .metrics.acquireMicroseconds += acquireDuration
        .metrics.maxAcquireMicroseconds = Math.max(.metrics.maxAcquireMicroseconds, acquireDuration)
        if status == DXGI_ERROR_WAIT_TIMEOUT
        {
            .metrics.unchangedFrames += 1
            if not .hasLast do
                fail SystemError{"screen capture did not provide an initial frame"}
            return false
        }
        if status < 0 do
            fail SystemError{"screen capture output was lost", errorID: cast(u64, cast #bit (u32, status))}
        .pending = true
        .pendingResource = resource
        let frameResource = unwrap resource
        if info.LastPresentTime == 0 and .hasLast
        {
            .metrics.unchangedFrames += 1
            // A pointer-only update does not change desktop pixels.
            .abortGrab()
            return false
        }
        .metrics.acquiredFrames += 1
        if .hasLast and info.AccumulatedFrames > 1 do
            .metrics.coalescedUpdates += cast(u64, info.AccumulatedFrames - 1)

        let x = cast(u32, .options.x - .outputBounds.left)
        let y = cast(u32, .options.y - .outputBounds.top)
        var copyLeft = 0'u32
        var copyTop = 0'u32
        var copyRight = cast(u32, .options.width)
        var copyBottom = cast(u32, .options.height)
        let outputWidth = cast(u64, .outputBounds.right - .outputBounds.left)
        let outputHeight = cast(u64, .outputBounds.bottom - .outputBounds.top)
        let selectedPixels = cast(u64, .options.width) * cast(u64, .options.height)
        // Small cropped staging textures mapped more slowly with partial GPU writes on this
        // device. Restrict metadata updates to selections covering most of an output.
        if .hasLast and selectedPixels * 4 >= outputWidth * outputHeight * 3
        {
            let changed = .changedBounds(duplication, info.TotalMetadataBufferSize,
                                         cast(s32, x), cast(s32, y))
            if changed.known
            {
                if not changed.changed
                {
                    .metrics.unchangedFrames += 1
                    .abortGrab()
                    return false
                }
                copyLeft = cast(u32, changed.bounds.left)
                copyTop = cast(u32, changed.bounds.top)
                copyRight = cast(u32, changed.bounds.right)
                copyBottom = cast(u32, changed.bounds.bottom)
                let unionPixels = cast(u64, copyRight - copyLeft) * (copyBottom - copyTop)
                // Several GPU copy commands pay off only when they avoid most of the union.
                .pendingMultiRect = changed.rectCount > 1 and changed.rectCount <= MaxSplitRects and
                                    changed.copiedPixels < unionPixels / 2
                if copyLeft or copyTop or copyRight != cast(u32, .options.width) or
                   copyBottom != cast(u32, .options.height) do
                    .metrics.partialFrames += 1
            }
        }

        var raw: LPVOID
        let textureId = IID_ID3D11Texture2D
        let unknown = cast(*IUnknown, cast(*void, frameResource))
        let queried = unknown.lpVtbl.QueryInterface(unknown, &textureId, &raw)
        if queried < 0
        {
            .abortGrab()
            fail SystemError{"screen capture frame is not a texture", errorID: cast(u64, cast #bit (u32, queried))}
        }
        let texture = cast(*ID3D11Texture2D, unwrap raw)
        .pendingTexture = texture

        let box = D3D11_BOX{x + copyLeft, y + copyTop, 0,
                            x + copyRight, y + copyBottom, 1}
        let context = unwrap .context
        let staging = unwrap .staging
        let submitStart = Time.monotonicMicroseconds()
        let targetResource = cast(*ID3D11Resource, cast(*void, staging))
        let sourceResource = cast(*ID3D11Resource, cast(*void, texture))
        if .pendingMultiRect
        {
            for rect in .changedRects
            {
                let part = D3D11_BOX{x + cast(u32, rect.left), y + cast(u32, rect.top), 0,
                                     x + cast(u32, rect.right), y + cast(u32, rect.bottom), 1}
                context.lpVtbl.CopySubresourceRegion(context, targetResource, 0,
                                                     cast(u32, rect.left), cast(u32, rect.top), 0,
                                                     sourceResource, 0, &part)
            }
        }
        else do
            context.lpVtbl.CopySubresourceRegion(context, targetResource, 0,
                                                 copyLeft, copyTop, 0, sourceResource, 0, &box)
        .pendingSubmitMicroseconds = Time.monotonicMicroseconds() - submitStart
        .pendingLeft   = copyLeft
        .pendingTop    = copyTop
        .pendingRight  = copyRight
        .pendingBottom = copyBottom
        return true
    }

    // Maps an earlier GPU copy and writes it into the composed bottom-up image.
    mtd finishGrab(target: *Image, destinationX: u64, destinationBottom: u64) fail
    {
        Swag.assert(.pending)
        defer .abortGrab()
        let context = unwrap .context
        let staging = unwrap .staging
        var mapped: D3D11_MAPPED_SUBRESOURCE
        let readbackStart = Time.monotonicMicroseconds()
        let mapStatus = context.lpVtbl.Map(context, cast(*ID3D11Resource, cast(*void, staging)), 0,
                                           D3D11_MAP_READ, 0, &mapped)
        if mapStatus < 0 do
            fail SystemError{"cannot read screen capture frame", errorID: cast(u64, cast #bit (u32, mapStatus))}
        let readbackDuration = .pendingSubmitMicroseconds + Time.monotonicMicroseconds() - readbackStart
        .metrics.readbackMicroseconds += readbackDuration
        .metrics.maxReadbackMicroseconds = Math.max(.metrics.maxReadbackMicroseconds, readbackDuration)
        defer context.lpVtbl.Unmap(context, cast(*ID3D11Resource, cast(*void, staging)), 0)

        let copyStart = Time.monotonicMicroseconds()
        if .pendingMultiRect
        {
            for rect in .changedRects do
                .copyMappedRect(target, &mapped, destinationX, destinationBottom, rect)
            .metrics.multiRectFrames += 1
        }
        else do
            .copyMappedRect(target, &mapped, destinationX, destinationBottom,
                            RECT{cast(s32, .pendingLeft), cast(s32, .pendingTop),
                                 cast(s32, .pendingRight), cast(s32, .pendingBottom)})
        .metrics.copyMicroseconds += Time.monotonicMicroseconds() - copyStart
        .updatedBounds = RECT{cast(s32, .pendingLeft), cast(s32, .pendingTop),
                              cast(s32, .pendingRight), cast(s32, .pendingBottom)}
        .hasLast = true
    }

    mtd copyMappedRect(target: *Image, mapped: const *D3D11_MAPPED_SUBRESOURCE,
                       destinationX, destinationBottom: u64, rect: RECT)
    {
        let rowBytes = cast(u64, rect.right - rect.left) * 4
        let source = cast(const [*] u8, unwrap mapped.pData)
        let destination = target.pixels.storage()
        let destinationStride = cast(u64, target.rowStride)
        let sourceTopRow = source + cast(u64, rect.top) * mapped.RowPitch + cast(u64, rect.left) * 4
        let destinationBottomRow = destination +
                                   (destinationBottom + cast(u64, .options.height) - 1 - cast(u64, rect.top)) * destinationStride +
                                   (destinationX + cast(u64, rect.left)) * 4
        copyMappedBgraRows(destinationBottomRow, destinationStride,
                           sourceTopRow, cast(u64, mapped.RowPitch), rowBytes,
                           cast(u64, rect.bottom - rect.top))
        .metrics.copiedPixels += cast(u64, rect.right - rect.left) * cast(u64, rect.bottom - rect.top)
    }

    mtd reopen(shared: *NativeSource? = null) fail
    {
        let options = .options
        // DXGI permits only one duplication of a given output in this process.
        .opDrop()
        var replacement = try NativeSource.open(options, shared)
        Core.swap(me, &replacement)
    }

    mtd opDrop()
    {
        .abortGrab()
        release(.staging)
        .staging = null
        release(.duplication)
        .duplication = null
        release(.output1)
        .output1 = null
        release(.output)
        .output = null
        release(.adapter)
        .adapter = null
        release(.context)
        .context = null
        release(.device)
        .device = null
    }
}

impl Source
{
    mtd mirrorRect(target: *Image, native: const *NativeSource,
                   x, bottom: u64, bounds: RECT)
    {
        let rowBytes = cast(u64, bounds.right - bounds.left) * 4
        let left = x + cast(u64, bounds.left)
        let stride = cast(u64, target.rowStride)
        for row in cast(u64, bounds.top) until cast(u64, bounds.bottom)
        {
            let offset = (bottom + cast(u64, native.options.height) - 1 - row) * stride + left * 4
            Memory.copy(target.pixels.storage() + offset,
                        .composed.pixels.storage() + offset, rowBytes)
        }
        .mirroredPixels += cast(u64, bounds.right - bounds.left) * cast(u64, bounds.bottom - bounds.top)
    }

    // Queue each output's GPU copy before any map waits for pixels on the CPU.
    mtd grabWindows(target: *Image, mirroring: bool)->bool fail
    {
        var fresh = false
        catch
        {
            for beginIndex in .sources.count
            {
                let native = .sources[beginIndex]
                discard try native.beginGrab()
            }
            if .sources.count > 1
            {
                for flushIndex in .sources.count
                {
                    let native = .sources[flushIndex]
                    if not native.pending do
                        continue
                    var flushed = false
                    for previous in flushIndex
                    {
                        let earlier = .sources[previous]
                        if earlier.pending and earlier.context == native.context
                        {
                            flushed = true
                            break
                        }
                    }
                    if not flushed do
                        native.flushReadback()
                }
            }

            for finishIndex in .sources.count
            {
                let native = .sources[finishIndex]
                if not native.pending do
                    continue
                let x = cast(u64, native.options.x - .options.x)
                let bottom = cast(u64, .options.height - (native.options.y - .options.y) - native.options.height)
                try native.finishGrab(&.composed, x, bottom)
                fresh = true
                if mirroring
                {
                    let mirrorStart = Time.monotonicMicroseconds()
                    if native.pendingMultiRect
                    {
                        for rect in native.changedRects do
                            .mirrorRect(target, native, x, bottom, rect)
                    }
                    else do
                        .mirrorRect(target, native, x, bottom, native.updatedBounds)
                    .composeMicroseconds += Time.monotonicMicroseconds() - mirrorStart
                }
            }
        }
        {
            for abortIndex in .sources.count do
                .sources[abortIndex].abortGrab()
            fail Swag.err
        }
        return fresh
    }
}

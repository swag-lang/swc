#global if #os == Swag.TargetOs.Windows

using Core, Core.Errors, Pixel, Win32

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
    updatedBounds: RECT
    metrics:      SourceMetrics
}

impl NativeSource
{
    private mtd includeChangedRect(changed: *ChangedBounds, rect: RECT, captureX, captureY: s32)
    {
        let left = Math.max(rect.left, captureX)
        let top = Math.max(rect.top, captureY)
        let right = Math.min(rect.right, captureX + .options.width)
        let bottom = Math.min(rect.bottom, captureY + .options.height)
        if right <= left or bottom <= top do
            return
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

    func open(options: SourceOptions)->NativeSource fail
    {
        if options.includeCursor do
            fail UnsupportedFormatError{"DXGI screen capture does not include a separate pointer yet"}
        var result: #returntype
        result.options = options
        let hr = D3D11CreateDevice(null, D3D_DRIVER_TYPE_HARDWARE, null,
                                   D3D11_CREATE_DEVICE_BGRA_SUPPORT, null, 0,
                                   D3D11_SDK_VERSION, &result.device, null, &result.context)
        if hr < 0 do
            fail SystemError{"cannot create screen capture graphics device", errorID: cast(u64, cast #bit (u32, hr))}

        let device = unwrap result.device
        let unknown = cast(*IUnknown, cast(*void, device))
        var raw: LPVOID
        let deviceId = IID_IDXGIDevice
        var status = unknown.lpVtbl.QueryInterface(unknown, &deviceId, &raw)
        if status < 0 do
            fail SystemError{"cannot query screen capture display device", errorID: cast(u64, cast #bit (u32, status))}
        let displayDevice = cast(*IDXGIDevice, unwrap raw)
        defer release(displayDevice)

        status = displayDevice.lpVtbl.GetAdapter(displayDevice, &result.adapter)
        if status < 0 do
            fail SystemError{"cannot find screen capture display adapter", errorID: cast(u64, cast #bit (u32, status))}
        let adapter = unwrap result.adapter
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

    mtd grabInto(target: *Image, destinationX: u64, destinationBottom: u64)->bool fail
    {
        .updatedBounds = RECT{}
        let duplication = unwrap .duplication
        let firstFrame = not .hasLast
        var info: DXGI_OUTDUPL_FRAME_INFO
        var resource: *IDXGIResource?
        let acquireStart = Time.monotonicMicroseconds()
        let status = duplication.lpVtbl.AcquireNextFrame(duplication, .hasLast ? 0 : 1000,
                                                          &info, &resource)
        .metrics.acquireMicroseconds += Time.monotonicMicroseconds() - acquireStart
        if status == DXGI_ERROR_WAIT_TIMEOUT
        {
            .metrics.unchangedFrames += 1
            if not .hasLast do
                fail SystemError{"screen capture did not provide an initial frame"}
            return false
        }
        if status < 0 do
            fail SystemError{"screen capture output was lost", errorID: cast(u64, cast #bit (u32, status))}
        defer discard duplication.lpVtbl.ReleaseFrame(duplication)
        let frameResource = unwrap resource
        defer release(frameResource)
        if info.LastPresentTime == 0 and .hasLast
        {
            .metrics.unchangedFrames += 1
            // A pointer-only update does not change desktop pixels.
            return false
        }
        .metrics.acquiredFrames += 1

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
                    return false
                }
                copyLeft = cast(u32, changed.bounds.left)
                copyTop = cast(u32, changed.bounds.top)
                copyRight = cast(u32, changed.bounds.right)
                copyBottom = cast(u32, changed.bounds.bottom)
                if copyLeft or copyTop or copyRight != cast(u32, .options.width) or
                   copyBottom != cast(u32, .options.height) do
                    .metrics.partialFrames += 1
            }
        }

        var raw: LPVOID
        let textureId = IID_ID3D11Texture2D
        let unknown = cast(*IUnknown, cast(*void, frameResource))
        let queried = unknown.lpVtbl.QueryInterface(unknown, &textureId, &raw)
        if queried < 0 do
            fail SystemError{"screen capture frame is not a texture", errorID: cast(u64, cast #bit (u32, queried))}
        let texture = cast(*ID3D11Texture2D, unwrap raw)
        defer release(texture)

        let box = D3D11_BOX{x + copyLeft, y + copyTop, 0,
                            x + copyRight, y + copyBottom, 1}
        let context = unwrap .context
        let staging = unwrap .staging
        let readbackStart = Time.monotonicMicroseconds()
        context.lpVtbl.CopySubresourceRegion(context, cast(*ID3D11Resource, cast(*void, staging)),
                                             0, copyLeft, copyTop, 0,
                                             cast(*ID3D11Resource, cast(*void, texture)), 0, &box)
        var mapped: D3D11_MAPPED_SUBRESOURCE
        let mapStatus = context.lpVtbl.Map(context, cast(*ID3D11Resource, cast(*void, staging)), 0,
                                           D3D11_MAP_READ, 0, &mapped)
        if mapStatus < 0 do
            fail SystemError{"cannot read screen capture frame", errorID: cast(u64, cast #bit (u32, mapStatus))}
        .metrics.readbackMicroseconds += Time.monotonicMicroseconds() - readbackStart
        defer context.lpVtbl.Unmap(context, cast(*ID3D11Resource, cast(*void, staging)), 0)

        let rowBytes = cast(u64, copyRight - copyLeft) * 4
        let source = cast(const [*] u8, unwrap mapped.pData)
        let destination = target.pixels.storage()
        let destinationStride = cast(u64, target.rowStride)
        let sourceTopRow = source + cast(u64, copyTop) * mapped.RowPitch + copyLeft * 4
        let destinationBottomRow = destination +
                                   (destinationBottom + cast(u64, .options.height) - 1 - copyTop) * destinationStride +
                                   (destinationX + copyLeft) * 4
        let copyStart = Time.monotonicMicroseconds()
        copyMappedBgraRows(destinationBottomRow, destinationStride,
                           sourceTopRow, cast(u64, mapped.RowPitch), rowBytes,
                           cast(u64, copyBottom - copyTop))
        .metrics.copyMicroseconds += Time.monotonicMicroseconds() - copyStart
        .metrics.copiedPixels += cast(u64, copyRight - copyLeft) * (copyBottom - copyTop)
        .updatedBounds = RECT{cast(s32, copyLeft), cast(s32, copyTop),
                              cast(s32, copyRight), cast(s32, copyBottom)}
        .hasLast = true
        return firstFrame or info.LastPresentTime != 0
    }

    mtd reopen() fail
    {
        var replacement = try NativeSource.open(.options)
        Core.swap(me, &replacement)
    }

    mtd opDrop()
    {
        release(.staging)
        release(.duplication)
        release(.output1)
        release(.output)
        release(.adapter)
        release(.context)
        release(.device)
    }
}

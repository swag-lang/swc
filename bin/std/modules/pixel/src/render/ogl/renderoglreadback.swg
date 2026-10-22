#global public

using Core, Ogl

// Transfers one OpenGL render-target rectangle to CPU memory without waiting for GPU completion.
//
// Keep the owning OpenGL context current for every operation. The source target must remain
// alive and unchanged until the transfer finishes or is cancelled. Pixels are tightly packed
// BGRA8, bottom row first, as in [[Pixel.IRenderer.readRenderTarget]]. Call
// [[Pixel.RenderOglReadback.release]] before destroying the context or dropping this value.
#[Swag.Opaque, Swag.NoCopy]
struct RenderOglReadback
{
    buffer:    GLuint
    capacity:  s64
    drawing:   GLsync
    transfer:  GLsync
    source:    GLuint
    sourceY:   s32
    sourceX:   s32
    byteCount: u64
    failed:    bool

    width:  s32
    height: s32
}

impl RenderOglReadback
{
    // Asserts that the owned OpenGL resources were released before this value goes away.
    mtd opDrop()
    {
        Swag.assert(.buffer == 0 and not .drawing and not .transfer)
    }

    // Reports whether a submitted rectangle has not yet been copied or cancelled.
    mtd const isPending()->bool => .drawing != null or .transfer != null

    // Reports a failed allocation or GPU transfer; release the value before retrying.
    mtd const hasFailed()->bool => .failed

    // Submits an in-bounds rectangle in top-left target coordinates without waiting for it.
    //
    // Returns false if OpenGL refuses the resources. Only one transfer may be pending.
    // Buffer storage is reused across submissions of the same or smaller size. The positive
    // rectangle must fit in a signed 32-bit byte count at four bytes per pixel.
    mtd submit(target: const *RenderTarget, x, y, width, height: s32)->bool
    {
        Swag.assert(not .isPending() and not .failed)
        Swag.assert(x >= 0 and y >= 0 and width > 0 and height > 0)
        Swag.assert(x <= target.colorBuffer.width - width and y <= target.colorBuffer.height - height)
        let bytes = cast(s64, width) * height * 4
        Swag.assert(bytes <= Swag.S32.Max)
        if not .buffer do
            glGenBuffers(1, &.buffer)
        if not .buffer
        {
            .failed = true
            return false
        }

        if .capacity < bytes
        {
            var previous: GLint
            glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &previous)
            glBindBuffer(GL_PIXEL_PACK_BUFFER, .buffer)
            defer glBindBuffer(GL_PIXEL_PACK_BUFFER, cast(GLuint, previous))
            glBufferData(GL_PIXEL_PACK_BUFFER, bytes, null, GL_STREAM_READ)
            var allocated: GLint
            glGetBufferParameteriv(GL_PIXEL_PACK_BUFFER, GL_BUFFER_SIZE, &allocated)
            if allocated < bytes
            {
                .failed = true
                return false
            }

            .capacity = bytes
        }

        .width     = width
        .height    = height
        .source    = cast(GLuint, target.handle)
        .sourceX   = x
        .sourceY   = target.colorBuffer.height - height - y
        .byteCount = cast(u64, bytes)
        .drawing   = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
        .failed    = .drawing == null
        glFlush()
        return not .failed
    }

    // Copies a completed transfer into borrowed bytes, optionally preserving row padding.
    //
    // Returns false while work is pending, when empty, or on failure; [[Pixel.RenderOglReadback.hasFailed]]
    // distinguishes failure. Every fence poll uses a zero timeout. The pixel transfer itself is
    // submitted only after drawing completes, so requesting it cannot wait on queued drawing.
    // `rowStride` is in bytes; zero means tightly packed. It must cover one row, and
    // `destination` must hold all rows. Bytes after each row's pixels are left unchanged.
    mtd tryCopyTo(destination: [..] u8, rowStride: u64 = 0)->bool
    {
        if .failed or not .isPending() do
            return false
        let rowBytes = cast(u64, .width) * 4
        let stride   = rowStride ? rowStride : rowBytes
        Swag.assert(stride >= rowBytes)
        Swag.assert(destination.count >= stride * cast(u64, (.height - 1)) + rowBytes)
        if .drawing
        {
            if not .ready(.drawing) do
                return false
            glDeleteSync(.drawing)
            .drawing = null
            .startTransfer()
            return false
        }

        if not .ready(.transfer) do
            return false
        var previous: GLint
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &previous)
        glBindBuffer(GL_PIXEL_PACK_BUFFER, .buffer)
        defer glBindBuffer(GL_PIXEL_PACK_BUFFER, cast(GLuint, previous))
        if stride == rowBytes
        {
            glGetBufferSubData(GL_PIXEL_PACK_BUFFER, 0, cast(s64, .byteCount), destination.buffer)
        }
        else
        {
            let mapped = glMapBuffer(GL_PIXEL_PACK_BUFFER, GL_READ_ONLY)
            if not mapped
            {
                .failed = true
                return false
            }

            let source = cast(const [*] u8, mapped)
            for row in cast(u64, .height) do
                Memory.copy(destination.buffer + row * stride, source + row * rowBytes, rowBytes)
            if glUnmapBuffer(GL_PIXEL_PACK_BUFFER) == GL_FALSE
            {
                .failed = true
                return false
            }
        }

        glDeleteSync(.transfer)
        .transfer = null
        return true
    }

    // Cancels a pending transfer without waiting, retaining buffer storage for later submissions.
    mtd cancel()
    {
        if .drawing do
            glDeleteSync(.drawing)
        if .transfer do
            glDeleteSync(.transfer)
        .drawing  = null
        .transfer = null
    }

    // Cancels pending work and releases the owned buffer without waiting for the GPU.
    //
    // Calling this on an empty value is harmless. The owning context must still be current.
    mtd release()
    {
        .cancel()
        if .buffer do
            glDeleteBuffers(1, &.buffer)
        .buffer   = 0
        .capacity = 0
        .failed   = false
    }
}

private impl RenderOglReadback
{
    mtd ready(fence: GLsync)->bool
    {
        let state = glClientWaitSync(fence, 0, 0)
        if state == GL_WAIT_FAILED do
            .failed = true
        return state == GL_ALREADY_SIGNALED or state == GL_CONDITION_SATISFIED
    }

    mtd startTransfer()
    {
        var framebuffer, buffer, alignment, rowLength, skipRows, skipPixels: GLint
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &framebuffer)
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer)
        glGetIntegerv(GL_PACK_ALIGNMENT, &alignment)
        glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength)
        glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows)
        glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels)
        defer
        {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, framebuffer))
            glBindBuffer(GL_PIXEL_PACK_BUFFER, cast(GLuint, buffer))
            glPixelStorei(GL_PACK_ALIGNMENT, alignment)
            glPixelStorei(GL_PACK_ROW_LENGTH, rowLength)
            glPixelStorei(GL_PACK_SKIP_ROWS, skipRows)
            glPixelStorei(GL_PACK_SKIP_PIXELS, skipPixels)
        }

        glBindFramebuffer(GL_READ_FRAMEBUFFER, .source)
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        glBindBuffer(GL_PIXEL_PACK_BUFFER, .buffer)
        glPixelStorei(GL_PACK_ALIGNMENT, 4)
        glPixelStorei(GL_PACK_ROW_LENGTH, 0)
        glPixelStorei(GL_PACK_SKIP_ROWS, 0)
        glPixelStorei(GL_PACK_SKIP_PIXELS, 0)
        glReadPixels(.sourceX, .sourceY, .width, .height, GL_BGRA, GL_UNSIGNED_BYTE, null)
        .transfer = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0)
        .failed   = .transfer == null
        glFlush()
    }
}

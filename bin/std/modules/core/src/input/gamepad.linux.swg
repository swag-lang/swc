#global if #os == Swag.TargetOs.Linux
#global namespace Input

private struct EvdevDevice
{
    descriptor: s32
    number:     u32
}

private func evdevHasBit(bits: const [..] u8, bit: u32)->bool
{
    return bit / 8 < bits.count and (bits[bit / 8] & (1 << (bit % 8))) != 0
}

private func evdevIoctl(fd: s32, request: u64, destination: *void)->s32 fail
{
    for
    {
        let result = Linux.ioctl(fd, request, destination)
        if result >= 0 do
            return result
        let error = Linux.errno()
        if error != Linux.EINTR do
            try Errors.failLinuxError(error)
    }
}

// Enumeration always uses read permission. Asking for rumble must not renumber read-only pads.
private func openEvdevGamepad(padIndex: u32, writable: bool = false)->EvdevDevice fail
{
    let directory = Linux.opendir("/dev/input".buffer)
    if not directory do
        try Errors.failLinuxError(Linux.errno(), "/dev/input")
    let opened = unwrap directory
    defer discard Linux.closedir(opened)
    var previous = -1's64
    for index in cast(u64, padIndex) + 1
    {
        var candidate = Swag.S64.Max
        var selected  = -1's32
        defer if selected >= 0 do
            discard Linux.close(selected)
        Linux.rewinddir(opened)
        for
        {
            let entry = Linux.readdir(opened)
            if not entry do
                break
            let name = entry.d_name
            if name[0] != 'e' or name[1] != 'v' or name[2] != 'e' or name[3] != 'n' or name[4] != 't' do
                continue
            var number = 0's64
            var digits = 0'u32
            for position in 5'u32 until name.count
            {
                let digit = name[position]
                if digit < '0' or digit > '9' do
                    break
                number = number * 10 + cast(s64, digit - '0')
                digits += 1
                if digits > 10 do
                    break
            }

            if not digits or
               digits > 10 or
               number > Swag.U32.Max or
               name[5 + digits] or
               number <= previous or
               number >= candidate do
                continue
            let fd = Linux.openat(Linux.dirfd(opened), &entry.d_name[0], Linux.O_RDONLY | Linux.O_NONBLOCK | Linux.O_CLOEXEC)
            if fd < 0 do
                continue
            var keep = false
            defer if not keep do
                discard Linux.close(fd)
            var keys: [96] u8
            var axes: [8] u8
            let keyResult  = catch evdevIoctl(fd, Linux.EVIOCGBIT(Linux.EV_KEY, keys.count), &keys) { continue }
            let axisResult = catch evdevIoctl(fd, Linux.EVIOCGBIT(Linux.EV_ABS, axes.count), &axes) { continue }
            if keyResult == 0 or
               axisResult == 0 or
               not evdevHasBit(keys, Linux.BTN_GAMEPAD) or
               not evdevHasBit(axes, Linux.ABS_X) or
               not evdevHasBit(axes, Linux.ABS_Y) do
                continue
            if selected >= 0 do
                discard Linux.close(selected)
            selected  = fd
            candidate = number
            keep      = true
        }

        if selected < 0 do
            try Errors.failLinuxError(Linux.ENODEV)
        if index == padIndex
        {
            if writable
            {
                let name = Format.toString("event%", candidate)
                let fd   = Linux.openat(Linux.dirfd(opened), name.storage(), Linux.O_RDWR | Linux.O_NONBLOCK | Linux.O_CLOEXEC)
                if fd < 0 do
                    try Errors.failLinuxError(Linux.errno())
                var keep = false
                defer if not keep do
                    discard Linux.close(fd)
                var original, replacement: Linux.stat
                if Linux.fstat(selected, &original) != 0 or Linux.fstat(fd, &replacement) != 0 do
                    try Errors.failLinuxError(Linux.errno())
                if original.st_dev != replacement.st_dev or
                   original.st_ino != replacement.st_ino or
                   original.st_rdev != replacement.st_rdev do
                    try Errors.failLinuxError(Linux.ENODEV)
                keep = true
                return {fd, cast(u32, candidate)}
            }

            let result = EvdevDevice{selected, cast(u32, candidate)}
            selected = -1
            return result
        }

        previous = candidate
    }

    try Errors.failLinuxError(Linux.ENODEV)
    return {-1, 0}
}

public impl Gamepad
{
    // Returns whether a readable evdev gamepad is connected at the index.
    //
    // Indices follow ascending event-node numbers and can change on hotplug or permission changes.
    // Devices must expose BTN_GAMEPAD and absolute X/Y axes; inaccessible devices are not listed.
    func isConnected(padIndex: u32)->bool
    {
        let device = catch openEvdevGamepad(padIndex) { return false }
        discard Linux.close(device.descriptor)
        return true
    }
}

// Convert the advertised native range without overflowing for full signed 32-bit axis ranges.
internal func normalizeEvdevAxis(info: Linux.input_absinfo, maximum: u16, invert: bool = false)->u32
{
    if info.maximum <= info.minimum do
        return 0
    let low      = cast(s64, info.minimum)
    let high     = cast(s64, info.maximum)
    let value    = Math.clamp(cast(s64, info.value), low, high)
    let position = invert ? high - value : value - low
    return cast(u32, position * maximum / (high - low))
}

internal func readRawGamepadState(padIndex: u32)->RawGamepadState fail
{
    let device = try openEvdevGamepad(padIndex)
    defer discard Linux.close(device.descriptor)
    let fd = device.descriptor
    var keys: [96] u8
    var axes: [8] u8
    discard try evdevIoctl(fd, Linux.EVIOCGKEY(keys.count), &keys)
    discard try evdevIoctl(fd, Linux.EVIOCGBIT(Linux.EV_ABS, axes.count), &axes)
    var result: #returntype
    let mappings = [Linux.BTN_SOUTH, Linux.BTN_EAST, Linux.BTN_WEST, Linux.BTN_NORTH,
                    Linux.BTN_THUMBL, Linux.BTN_THUMBR, Linux.BTN_START, Linux.BTN_SELECT,
                    Linux.BTN_TL, Linux.BTN_TR, Linux.BTN_DPAD_UP, Linux.BTN_DPAD_DOWN,
                    Linux.BTN_DPAD_LEFT, Linux.BTN_DPAD_RIGHT]
    let buttons: [14] RawGamepadButtons = [.A, .B, .X, .Y, .LeftStick, .RightStick, .Start, .Back,
                                           .LeftShoulder, .RightShoulder, .DPadUp, .DPadDown, .DPadLeft, .DPadRight]
    for code, index in mappings where evdevHasBit(keys, code) do
        result.buttons |= buttons[index]

    func axis(fd: s32, axes: const [..] u8, code: u32)->Linux.input_absinfo fail
    {
        var info: #returntype
        if evdevHasBit(axes, code) do
            discard try evdevIoctl(fd, Linux.EVIOCGABS(code), &info)
        return info
    }

    func stick(info: Linux.input_absinfo, invert: bool = false)->s16
    {
        if info.maximum <= info.minimum do
            return 0
        return cast(s16, cast(s32, normalizeEvdevAxis(info, 65535, invert)) - 32768)
    }

    result.leftStickX   = stick(try axis(fd, axes, Linux.ABS_X))
    result.leftStickY   = stick(try axis(fd, axes, Linux.ABS_Y), true)
    result.rightStickX  = stick(try axis(fd, axes, Linux.ABS_RX))
    result.rightStickY  = stick(try axis(fd, axes, Linux.ABS_RY), true)
    result.leftTrigger  = cast(u8, normalizeEvdevAxis(try axis(fd, axes, Linux.ABS_Z), 255))
    result.rightTrigger = cast(u8, normalizeEvdevAxis(try axis(fd, axes, Linux.ABS_RZ), 255))
    let hatX = try axis(fd, axes, Linux.ABS_HAT0X)
    let hatY = try axis(fd, axes, Linux.ABS_HAT0Y)
    if hatX.value < 0 do
        result.buttons |= .DPadLeft
    if hatX.value > 0 do
        result.buttons |= .DPadRight
    if hatY.value < 0 do
        result.buttons |= .DPadUp
    if hatY.value > 0 do
        result.buttons |= .DPadDown
    return result
}

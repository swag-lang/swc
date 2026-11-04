#global if #os == Swag.TargetOs.Linux
#global namespace Input

// Kernel effects belong to an open descriptor. Native storage avoids borrowing a caller allocator.
private struct EvdevRumble
{
    next:          *EvdevRumble?
    index:         u32
    descriptor:    s32
    effect:        s16
    device:        u64
    inode:         u64
    specialDevice: u64
}

private var g_RumbleMutex:    Swag.Mutex
private var g_RumbleEffects:  *EvdevRumble?
private var g_RumbleStopping: bool

#init
{
    g_RumbleMutex.lock()
    g_RumbleStopping = false
    g_RumbleMutex.unlock()
}

// Caller holds the mutex. Closing the evdev file removes all effects created through that file.
private func removeEvdevRumble(index: u32)
{
    var link = &g_RumbleEffects
    for
    {
        let state = link[]
        if not state do
            return
        if state.index == index
        {
            link[] = state.next
            discard Linux.close(state.descriptor)
            Linux.free(state)
            return
        }

        link = &state.next
    }
}

#drop
{
    g_RumbleMutex.lock()
    defer g_RumbleMutex.unlock()
    g_RumbleStopping = true
    for
    {
        let state = g_RumbleEffects
        if not state do
            break
        removeEvdevRumble(state.index)
    }
}

public impl Gamepad
{
    // Sets evdev strong/weak rumble intensities, clamping finite speeds to 0..1.
    //
    // Requires a writable device advertising FF_RUMBLE. Linux maps left to the strong motor
    // and right to the weak motor; physical placement is device-specific. Zero stops and releases
    // an owned effect. Otherwise the effect remains until updated, stopped, disconnected or Core
    // shutdown. A native failure releases that slot's previous effect. Hotplug may renumber slots.
    func setVibration(padIndex: u32, left, right: f32) fail
    {
        if not Math.isFinite(left) or not Math.isFinite(right) do
            fail Errors.BadParameterError{"gamepad vibration speeds must be finite"}
        g_RumbleMutex.lock()
        defer g_RumbleMutex.unlock()
        if g_RumbleStopping do
            fail Errors.BadParameterError{"gamepad services have shut down"}
        defer #fail removeEvdevRumble(padIndex)
        let device  = try openEvdevGamepad(padIndex, writable: true)
        var adopted = false
        defer if not adopted do
            discard Linux.close(device.descriptor)
        var capabilities: [16] u8
        discard try evdevIoctl(device.descriptor, Linux.EVIOCGBIT(Linux.EV_FF, capabilities.count), &capabilities)
        if not evdevHasBit(capabilities, Linux.FF_RUMBLE) do
            try Errors.failLinuxError(Linux.ENOTSUP)
        let strong = cast(u16, Math.saturate(left) * 65535)
        let weak   = cast(u16, Math.saturate(right) * 65535)
        if strong == 0 and weak == 0
        {
            removeEvdevRumble(padIndex)
            return
        }

        var identity: Linux.stat
        if Linux.fstat(device.descriptor, &identity) != 0 do
            try Errors.failLinuxError(Linux.errno())
        var state = g_RumbleEffects
        while state and state.index != padIndex do
            state = state.next
        if state and
           (state.device != identity.st_dev or
            state.inode != identity.st_ino or
            state.specialDevice != identity.st_rdev)
        {
            removeEvdevRumble(padIndex)
            state = null
        }

        if not state
        {
            let memory = Linux.calloc(1, #sizeof(EvdevRumble))
            if not memory do
                try Errors.failLinuxError(Linux.ENOMEM)
            let created = cast(*EvdevRumble, unwrap memory)
            created.index         = padIndex
            created.descriptor    = device.descriptor
            created.effect        = -1
            created.device        = identity.st_dev
            created.inode         = identity.st_ino
            created.specialDevice = identity.st_rdev
            created.next          = g_RumbleEffects
            g_RumbleEffects       = created
            state                 = created
            adopted               = true
        }

        let active = state
        var effect: Linux.ff_effect
        effect.type = Linux.FF_RUMBLE
        effect.id   = active.effect

        // A zero replay length requests continuous playback; closing the descriptor stops it.
        let rumble = cast(*Linux.ff_rumble_effect, cast(*void, &effect.u))
        rumble.strong_magnitude = strong
        rumble.weak_magnitude   = weak
        discard try evdevIoctl(active.descriptor, Linux.EVIOCSFF, &effect)
        if effect.id < 0 do
            try Errors.failLinuxError(Linux.EIO)
        active.effect = effect.id
        var event = Linux.input_event{type: Linux.EV_FF, code: cast(u16, effect.id), value: 1}
        for
        {
            let written = Linux.write(active.descriptor, &event, #sizeof(event))
            if written == #sizeof(event) do
                return
            if written < 0
            {
                let error = Linux.errno()
                if error == Linux.EINTR do
                    continue
                try Errors.failLinuxError(error)
            }

            try Errors.failLinuxError(Linux.EIO)
        }
    }
}

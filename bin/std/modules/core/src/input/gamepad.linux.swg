#global if #os == Swag.TargetOs.Linux
#global namespace Input

public impl Gamepad
{
    // Returns whether a readable gamepad is connected at `padIndex`.
    //
    // Linux indices enumerate evdev gamepads in ascending event-node order. Devices without
    // read permission are not enumerated; attaching or removing a device can change indices.
    func isConnected(padIndex: u32)->bool
    {
        let directory = Linux.opendir("/dev/input".buffer)
        if not directory do
            return false
        defer discard Linux.closedir(unwrap directory)

        var previous = -1's64
        for index in cast(u64, padIndex) + 1
        {
            var candidate = Swag.S64.Max
            Linux.rewinddir(directory)
            for
            {
                let entry = Linux.readdir(directory)
                if not entry do
                    break
                let name = entry.d_name
                if name[0] != 'e' or
                   name[1] != 'v' or
                   name[2] != 'e' or
                   name[3] != 'n' or
                   name[4] != 't' do
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

                let descriptor = Linux.openat(Linux.dirfd(directory), &entry.d_name[0], Linux.O_RDONLY | Linux.O_NONBLOCK | Linux.O_CLOEXEC)
                if descriptor < 0 do
                    continue
                defer discard Linux.close(descriptor)

                var keys: [96] u8
                var axes: [8] u8
                if Linux.ioctl(descriptor, Linux.EVIOCGBIT(Linux.EV_KEY, keys.count), &keys) < 0 or
                   Linux.ioctl(descriptor, Linux.EVIOCGBIT(Linux.EV_ABS, axes.count), &axes) < 0 do
                    continue
                if not (keys[Linux.BTN_GAMEPAD / 8] & (1 << (Linux.BTN_GAMEPAD % 8))) or (axes[0] & 3) != 3 do
                    continue
                candidate = number
            }

            if candidate == Swag.S64.Max do
                return false
            if index == padIndex do
                return true
            previous = candidate
        }

        return false
    }
}

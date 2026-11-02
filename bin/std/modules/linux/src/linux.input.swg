#global if #os == Swag.TargetOs.Linux
#global export

const EV_KEY      = 1'u32
const EV_ABS      = 3'u32
const BTN_GAMEPAD = 0x130'u32
const ABS_X       = 0'u32
const ABS_Y       = 1'u32

func EVIOCGBIT(ev: u32, len: u32)->u64 => (2'u64 << 30) | (cast(u64, len) << 16) | (0x45'u64 << 8) | (0x20 + ev)

const EV_FF          = 0x15'u16
const ABS_Z          = 2'u32
const ABS_RX         = 3'u32
const ABS_RY         = 4'u32
const ABS_RZ         = 5'u32
const ABS_HAT0X      = 16'u32
const ABS_HAT0Y      = 17'u32
const BTN_SOUTH      = 0x130'u32
const BTN_EAST       = 0x131'u32
const BTN_NORTH      = 0x133'u32
const BTN_WEST       = 0x134'u32
const BTN_TL         = 0x136'u32
const BTN_TR         = 0x137'u32
const BTN_SELECT     = 0x13A'u32
const BTN_START      = 0x13B'u32
const BTN_THUMBL     = 0x13D'u32
const BTN_THUMBR     = 0x13E'u32
const BTN_DPAD_UP    = 0x220'u32
const BTN_DPAD_DOWN  = 0x221'u32
const BTN_DPAD_LEFT  = 0x222'u32
const BTN_DPAD_RIGHT = 0x223'u32
const FF_RUMBLE      = 0x50'u16

struct input_absinfo
{
    public
    {
        value:      s32
        minimum:    s32
        maximum:    s32
        fuzz:       s32
        flat:       s32
        resolution: s32
    }
}

// Native x86-64 input_event uses a timeval (seconds and microseconds), not a timespec.
struct input_event
{
    public
    {
        seconds:      s64
        microseconds: s64
        type:         u16
        code:         u16
        value:        s32
    }
}

struct ff_trigger
{
    public
    {
        button:   u16
        interval: u16
    }
}

struct ff_replay
{
    public
    {
        length: u16
        delay:  u16
    }
}

struct ff_rumble_effect
{
    public
    {
        strong_magnitude: u16
        weak_magnitude:   u16
    }
}

// u is the native 32-byte effect union, aligned to eight bytes on GNU/Linux x86-64.
struct ff_effect
{
    public
    {
        type:      u16
        id:        s16
        direction: u16
        trigger:   ff_trigger
        replay:    ff_replay
        u:         [4] u64
    }
}

#assert(#sizeof(input_absinfo) == 24)
#assert(#sizeof(input_event) == 24)
#assert(#sizeof(ff_effect) == 48)

func EVIOCGKEY(len: u32)->u64  => (2'u64 << 30) | (cast(u64, len) << 16) | (0x45'u64 << 8) | 0x18
func EVIOCGABS(axis: u32)->u64 => (2'u64 << 30) | (24'u64 << 16) | (0x45'u64 << 8) | (0x40 + axis)
const EVIOCSFF  = 0x40304580'u64
const EVIOCRMFF = 0x40044581'u64

#assert(#offsetof(ff_effect.u) == 16)
#assert(#offsetof(ff_effect.replay) == 10)
#assert(#offsetof(input_event.type) == 16)

#global if #os == Swag.TargetOs.Linux
#global export

const EV_KEY      = 1'u32
const EV_ABS      = 3'u32
const BTN_GAMEPAD = 0x130'u32
const ABS_X       = 0'u32
const ABS_Y       = 1'u32

func EVIOCGBIT(ev: u32, len: u32)->u64 => (2'u64 << 30) | (cast(u64, len) << 16) | (0x45'u64 << 8) | (0x20 + ev)

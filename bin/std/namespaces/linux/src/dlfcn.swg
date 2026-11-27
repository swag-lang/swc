#global if #os == Swag.TargetOs.Linux
#global public

const RTLD_LOCAL    = 0_s32
const RTLD_LAZY     = 1_s32
const RTLD_NOW      = 2_s32
const RTLD_NODELETE = 0x1000_s32

#[Swag.Foreign(module: "libc.so.6", link: "dl", callconv: .C)]
{
    func dlopen(filename: const [*] u8?, flags: s32)->*void?
    func dlclose(handle: *void)->s32
    func dlsym(handle: *void, symbol: const [*] u8)->*void?
    func dlerror()->[*] u8?
}

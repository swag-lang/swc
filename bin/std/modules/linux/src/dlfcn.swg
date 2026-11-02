#global if #os == Swag.TargetOs.Linux
#global export

const RTLD_LOCAL = 0's32
const RTLD_LAZY  = 1's32
const RTLD_NOW   = 2's32

#[Swag.Foreign(module: "libc.so.6", link: "dl", callconv: .C)]
{
    func dlopen(filename: const [*] u8?, flags: s32)->*void?
    func dlclose(handle: *void)->s32
    func dlsym(handle: *void, symbol: const [*] u8)->*void?
    func dlerror()->[*] u8?
}

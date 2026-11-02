#global if #os == Swag.TargetOs.Linux
#global export

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func realpath(path: const [*] u8, resolved_path: [*] u8?)->[*] u8?
    func calloc(nmemb: u64, size: u64)->*void?
    func free(ptr: *void?)
    func mkdtemp(template: [*] u8)->[*] u8?
    func getenv(name: const [*] u8)->[*] u8?
    #[Swag.NoReturn]
    func exit(status: s32)
}

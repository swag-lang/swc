#global if #os == Swag.TargetOs.Linux
#global export

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func mkdtemp(template: [*] u8)->[*] u8?
    func getenv(name: const [*] u8)->[*] u8?
    #[Swag.NoReturn]
    func exit(status: s32)
}

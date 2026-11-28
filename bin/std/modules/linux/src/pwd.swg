#global if #os == Swag.TargetOs.Linux
#global export

struct passwd
{
    public
    {
        pw_name:   [*] u8?
        pw_passwd: [*] u8?
        pw_uid:    u32
        pw_gid:    u32
        pw_gecos:  [*] u8?
        pw_dir:    [*] u8?
        pw_shell:  [*] u8?
    }
}

#assert(#sizeof(passwd) == 48)
#assert(#offsetof(passwd.pw_dir) == 32)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func getpwuid_r(uid: u32, pwd: *passwd, buf: [*] u8, buflen: u64, result: *(*passwd?))->s32

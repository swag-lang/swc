#global if #os == Swag.TargetOs.Linux
#global export

const WNOHANG = 1's32

// Native wait-status macros exposed as functions; these do not wait or consume a child status.
#[Swag.Inline]
func WIFEXITED(status: s32)->bool => (status & 0x7F) == 0
#[Swag.Inline]
func WEXITSTATUS(status: s32)->s32 => (status >> 8) & 0xFF
#[Swag.Inline]
func WIFSIGNALED(status: s32)->bool => (status & 0x7F) != 0 and (status & 0x7F) != 0x7F
#[Swag.Inline]
func WTERMSIG(status: s32)->s32 => status & 0x7F

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func waitpid(pid: s32, wstatus: *s32?, options: s32)->s32

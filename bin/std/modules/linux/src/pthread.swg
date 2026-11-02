#global if #os == Swag.TargetOs.Linux
#global export

// The glibc x86-64 pthread identity; it remains valid until a successful join.
alias pthread_t = u64

// C entry point passed to pthread_create; its result can be retrieved by pthread_join.
#[Swag.CallingConvention(.C)]
alias PthreadEntry = func(*void?)->*void?

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func pthread_create(thread: *pthread_t, attributes: const *void?, entry: PthreadEntry, argument: *void?)->s32
    func pthread_join(thread: pthread_t, result: *(*void?)?)->s32
    func pthread_tryjoin_np(thread: pthread_t, result: *(*void?)?)->s32
    func pthread_self()->pthread_t
    func pthread_getschedparam(thread: pthread_t, policy: *s32, parameter: *sched_param)->s32
    func pthread_setschedparam(thread: pthread_t, policy: s32, parameter: const *sched_param)->s32
}

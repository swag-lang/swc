#global if #os == Swag.TargetOs.Linux
#global export

const SCHED_OTHER = 0's32

struct sched_param
{
    public sched_priority: s32
}

#assert(#sizeof(sched_param) == 4)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func sched_yield()->s32
    func sched_getaffinity(pid: s32, cpusetsize: u64, mask: *void)->s32
}

#global if #os == Swag.TargetOs.Linux
#global export

const PRIO_PROCESS = 0's32
const PRIO_PGRP    = 1's32
const PRIO_USER    = 2's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func getpriority(which: s32, who: u32)->s32
    func setpriority(which: s32, who: u32, priority: s32)->s32
}

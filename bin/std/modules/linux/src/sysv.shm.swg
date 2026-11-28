#global if #os == Swag.TargetOs.Linux
#global export

// System V shared memory is used by X11 MIT-SHM. IPC_PRIVATE is 0,
// IPC_CREAT | 0600 is 0x380, and IPC_RMID is 0 on Linux.
#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func shmget(key: s32, size: u64, flags: s32)->s32
    func shmat(id: s32, address: const *void?, flags: s32)->*void?
    func shmdt(address: const *void)->s32
    func shmctl(id: s32, command: s32, buffer: *void?)->s32
}

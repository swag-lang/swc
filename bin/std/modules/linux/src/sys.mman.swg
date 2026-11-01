#global if #os == Swag.TargetOs.Linux
#global export

const PROT_NONE  = 0's32
const PROT_READ  = 1's32
const PROT_WRITE = 2's32
const PROT_EXEC  = 4's32

const MAP_SHARED    = 0x01's32
const MAP_PRIVATE   = 0x02's32
const MAP_ANONYMOUS = 0x20's32

const MFD_CLOEXEC = 1'u32

const MADV_PAGEOUT = 21's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func memfd_create(name: const [*] u8, flags: u32)->s32
    func mmap(addr: *void?, length: u64, prot: s32, flags: s32, fd: s32, offset: s64)->*void?
    func munmap(addr: *void?, length: u64)->s32
    func madvise(addr: *void?, length: u64, advice: s32)->s32
}

#global private

using Core

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func mprotect(start: *void, size: u64, protection: s32)->s32
    func getpagesize()->s32
}

func guardedInput(page: u64)->[*] u8
{
    let mapping = Linux.mmap(null, 3 * page, Linux.PROT_NONE, Linux.MAP_PRIVATE | Linux.MAP_ANONYMOUS, -1, 0)
    Swag.require(mapping != null and cast(u64, mapping) != Swag.U64.Max)
    let bytes = cast([*] u8, mapping)
    Swag.require(mprotect(bytes + page, page, Linux.PROT_READ | Linux.PROT_WRITE) == 0)
    return bytes
}

internal func checkGuardedInputs()
{
    let page = cast(u64, getpagesize())
    Swag.require(page >= 1024)
    let a = guardedInput(page)
    defer Swag.require(Linux.munmap(a, 3 * page) == 0)
    let b = guardedInput(page)
    defer Swag.require(Linux.munmap(b, 3 * page) == 0)
    let empty   = cast(const [..] u8, "")
    var checked = 0'u64

    for side in 2
    {
        for count in 258
        {
            let start = side == 0 ? page : 2 * page - count
            let left  = Swag.makeSlice(a + start, count)
            let right = Swag.makeSlice(b + start, count)
            if count
            {
                Memory.set(a + start, 0x3C'u8, count)
                Memory.set(b + start, 0x3C'u8, count)
            }

            Swag.require(Crypto.constantTimeEqual(left, right))
            checked += 1
            if count
            {
                Swag.require(not Crypto.constantTimeEqual(empty, right))
                checked += 1
            }

            for position in count
            {
                (b + start)[position] ^= 1
                Swag.require(not Crypto.constantTimeEqual(left, right))
                (b + start)[position] ^= 1
                checked += 1
            }
        }
    }

    Console.println(checked, " guarded comparisons passed")
}

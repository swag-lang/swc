#global namespace InlineMem

#[Swag.Inline]
public func blockCopy(dest: [*] void, src: const [*] void, size: u64)
{
    if size do
        @memcpy(dest, src, size)
}

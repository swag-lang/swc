#global namespace InlineMem

#[Swag.Inline]
public func blockCopy(dest: [*] void, src: const [*] void, size: u64)
{
    if size
    {
        Swag.memcpy(dest, src, size)
    }
}

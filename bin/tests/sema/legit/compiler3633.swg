#global fileprivate // swc-option sema-only
#global skip
struct Image {}

impl Image
{
    public enum MixMode
    {
        Copy
    }

    mtd doMix(mode: MixMode = Copy) {}
}

#global fileprivate // swc-option sema-only
#global skip
struct Image {}

impl Image
{
    enum AA
    {
        Z
    }

    func fill(me, x: AA)
    {
        var f = {x, me}
    }
}

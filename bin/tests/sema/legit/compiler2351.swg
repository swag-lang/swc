#global fileprivate // swc-option sema-only
#global skip
struct AA {}

impl AA
{
    func create()->{ me1: AA }
    {
        var result: retval
        return result
    }
}

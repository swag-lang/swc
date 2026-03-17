#global fileprivate // swc-option sema-only
#global skip
struct(T) Arr {}

func titi()
{
    var map: Arr's32

    func count(m: #decltype(map))
    {
        return
    }
}

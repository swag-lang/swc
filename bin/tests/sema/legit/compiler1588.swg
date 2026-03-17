#global fileprivate // swc-option sema-only
#global skip
//
//#global testerror

struct(T) B {}

impl B
{
    func emplace(me)
    {
        let y = T
        @assert(#typeof(y) == const *Swag.TypeInfoNative)
    }
}

#test
{
    var arr: B's32
    arr.emplace()
}

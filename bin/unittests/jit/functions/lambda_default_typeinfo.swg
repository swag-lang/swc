#global private

#test
{
    let cb = func(info = #typeof([1, 2.5]))->u64
    {
        #assert(#typeof(info) == const *TypeInfoArray)
        return cast(u64) info.totalCount
    }

    Swag.assert(cb() == 2)
    Swag.assert(cb(#typeof([1, 2, 3])) == 3)
}

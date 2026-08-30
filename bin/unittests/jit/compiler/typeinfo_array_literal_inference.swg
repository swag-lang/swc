#test
{
    let items = [#typeof([1, 2.5]), #typeof([4, 5])]

    #assert(#typeof(items) == [2] const *TypeInfoArray)
    Swag.assert(items[0] == #type const [2] f32)
    Swag.assert(items[1] == #type const [2] s32)
    Swag.assert(items[0].totalCount == 2)
    Swag.assert(items[1].finalType == s32)
}

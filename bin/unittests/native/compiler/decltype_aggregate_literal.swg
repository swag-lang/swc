#global private

var wide: #decltype([1, 5_000_000_000]) = [1, 5_000_000_000]

#test
{
    let idx = 1

    #assert(#typeof(wide[0]) == s64)
    #assert(#typeof(wide[idx]) == s64)
    Swag.require(wide[0] == 1_s64)
    Swag.require(wide[idx] == 5_000_000_000_s64)
}

#global private
using Swag

// A type value converts to bool under the logical operators and in a ternary. The values are
// bound as 'typeinfo' variables: a '#type' constant carries a concrete 'const *TypeInfoXxx',
// which a condition refuses because the answer could only be true.

#test
{
    var arrayType:  typeinfo = #type const [2] f32
    var funcType:   typeinfo = #type func()->void
    var scalarType: typeinfo = #type s32

    let both     = arrayType and true
    let either   = false or funcType
    let selected = scalarType ? 10 : 20

    @assert(both)
    @assert(either)
    @assert(selected == 10)
}

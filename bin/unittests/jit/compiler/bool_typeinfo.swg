#global private
using Swag

// A type value converts to bool under the logical operators and in a ternary. The values are
// bound as '#null typeinfo' variables: a type that can never be null refuses the question,
// because the answer could only be true.

#test
{
    var arrayType:  #null typeinfo = #type const [2] f32
    var funcType:   #null typeinfo = #type func()->void
    var scalarType: #null typeinfo = #type s32

    let both     = arrayType and true
    let either   = false or funcType
    let selected = scalarType ? 10 : 20

    Swag.assert(both)
    Swag.assert(either)
    Swag.assert(selected == 10)

    arrayType = null
    Swag.assert(!arrayType)
}

#global private

var WIDE_ARRAY_SIZE = #sizeof([1, 5_000_000_000])
var WIDE_ARRAY_ALIGN = #alignof([1, 5_000_000_000])
var STRUCT_FIELD_SIZE = #sizeof({values: [9, 4, 1], bias: 1}.values)
var STRUCT_FIELD_ALIGN = #alignof({values: [9, 4, 1], bias: 1}.values)

#test
{
    @assert(WIDE_ARRAY_SIZE == 16)
    @assert(WIDE_ARRAY_ALIGN == 8)
    @assert(STRUCT_FIELD_SIZE == 12)
    @assert(STRUCT_FIELD_ALIGN == 4)
}

#global private

var WIDE_ARRAY_SIZE    = #sizeof([1, 5_000_000_000])
var WIDE_ARRAY_ALIGN   = #alignof([1, 5_000_000_000])
var STRUCT_FIELD_SIZE  = #sizeof({values: [9, 4, 1], bias: 1}.values)
var STRUCT_FIELD_ALIGN = #alignof({values: [9, 4, 1], bias: 1}.values)

#test
{
    Swag.require(WIDE_ARRAY_SIZE == 16)
    Swag.require(WIDE_ARRAY_ALIGN == 8)
    Swag.require(STRUCT_FIELD_SIZE == 12)
    Swag.require(STRUCT_FIELD_ALIGN == 4)
}

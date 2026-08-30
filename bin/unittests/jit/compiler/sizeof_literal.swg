#global private

var SIZEOF_INT    = #sizeof(1)
var ALIGNOF_INT   = #alignof(1)
var SIZEOF_FLOAT  = #sizeof(2.5)
var ALIGNOF_FLOAT = #alignof(2.5)

#test
{
    Swag.assert(SIZEOF_INT == 4)
    Swag.assert(ALIGNOF_INT == 4)
    Swag.assert(SIZEOF_FLOAT == 4)
    Swag.assert(ALIGNOF_FLOAT == 4)
}

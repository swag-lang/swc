#global private

// compileString borrows a string descriptor through the Swag interface ABI.
// A native host callback must not reinterpret that descriptor as host by-value lanes.
#run
{
    let source = "#test { Swag.assert(17 * 3 == 51) }\nTHIS_SUFFIX_IS_NOT_SWAG"
    let code   = source[0 until source.count - 23]
    Swag.compiler().compileString(code)
}

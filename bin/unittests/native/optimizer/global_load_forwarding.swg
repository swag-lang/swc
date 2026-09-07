#global private

var g_Zero: u64
var g_Initialized = 11'u64

#[Swag.NoInline]
func repeatedGlobal()->u64 => g_Zero + g_Zero

#[Swag.NoInline]
func distinctGlobals()->u64 => g_Zero + g_Initialized

#[Swag.NoInline]
func reloadAfterStore(address: *u64, value: u64)->u64
{
    let before = g_Zero
    address[] = value
    return before + g_Zero
}

#test
{
    g_Zero        = 7
    g_Initialized = 11
    Swag.assert(repeatedGlobal() == 14)
    Swag.assert(distinctGlobals() == 18)
    Swag.assert(reloadAfterStore(&g_Zero, 31) == 38)
    Swag.assert(reloadAfterStore(&g_Initialized, 41) == 62)
    Swag.assert(distinctGlobals() == 72)
}

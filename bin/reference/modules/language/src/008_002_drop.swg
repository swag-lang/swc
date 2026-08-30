#global private

/**
# 'Swag.drop' Intrinsic
The 'Swag.drop' intrinsic calls the `opDrop` method if it is defined for the struct.
This ensures that any necessary cleanup operations (such as freeing resources)
are performed before the variable is reinitialized. 'Swag.drop' is particularly useful
in resource management, where explicit cleanup is required before resetting the variable.
*/
#test
{
    struct RGB
    {
        r = 1
        g = 2
        b = 3
    }

    var rgb: [4] RGB

    Swag.drop(&rgb, 4)     // If RGB defines opDrop, it will be invoked here for each element

    Swag.init(&rgb, 4)(5, 6, 7)     // Reinitialize array elements after dropping
    Swag.assert(rgb[3].r == 5)
    Swag.assert(rgb[3].g == 6)
    Swag.assert(rgb[3].b == 7)
}

#global private

/**
# 'Swag.init' Intrinsic
Reinitializes a variable or memory region to either its type default value
or a provided custom value (tuple for aggregates).
*/

/**
# Scalars - Default Initialization
Reinitialize a single variable to its default value.
*/
#test
{
    var x = 666
    Swag.init(x)     // Reset variable 'x' to its default (0)
    Swag.assert(x == 0)
}

/**
# Scalars - Initialization with a Specific Value
Reinitialize a variable with a custom value instead of its default.
*/
#test
{
    var x = 666'f32
    Swag.init(x)(3.14)     // Initialize variable 'x' with 3.14 instead of 0
    Swag.assert(x == 3.14)
}

/**
# Arrays - Count-Based Default Initialization
Reinitialize a specified number of elements in an array or memory block.
*/
#test
{
    var x = [1, 2]

    Swag.init(&x, 2)     // Reset first 2 elements to their default (0)
    Swag.assert(x[0] == 0)
    Swag.assert(x[1] == 0)

    x[0] = 1
    x[1] = 2

    Swag.init(x)     // Reset the entire array to default values
    Swag.assert(x[0] == 0)
    Swag.assert(x[1] == 0)
}

/**
# Arrays - Initialization with a Specific Value
Initialize all targeted elements in an array to a given value.
*/
#test
{
    var x = [1, 2]

    Swag.init(&x, 2)(555)     // Initialize both elements to 555
    Swag.assert(x[0] == 555)
    Swag.assert(x[1] == 555)
}

/**
# Structs - Reset to Declared Defaults
Reinitialize a struct instance to its declared default field values.
*/
#test
{
    struct RGB
    {
        r = 1
        g = 2
        b = 3
    }

    var rgb = RGB{10, 20, 30}
    Swag.assert(rgb.r == 10)
    Swag.assert(rgb.g == 20)
    Swag.assert(rgb.b == 30)

    Swag.init(rgb)     // Reset struct fields to their declared defaults
    Swag.assert(rgb.r == 1)
    Swag.assert(rgb.g == 2)
    Swag.assert(rgb.b == 3)
}

/**
# Structs - Initialization with Specific Field Values
Reinitialize a struct instance with custom field values.
*/
#test
{
    struct RGB
    {
        r = 1
        g = 2
        b = 3
    }

    var rgb = RGB{10, 20, 30}
    Swag.assert(rgb.r == 10)
    Swag.assert(rgb.g == 20)
    Swag.assert(rgb.b == 30)

    Swag.init(rgb)(5, 6, 7)     // Assign new custom values to all struct fields
    Swag.assert(rgb.r == 5)
    Swag.assert(rgb.g == 6)
    Swag.assert(rgb.b == 7)
}

/**
# Arrays of Structs - Bulk Initialization and Reinitialization
Reinitialize all elements of an array of structs with specified field values.
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

    Swag.init(&rgb, 4)(5, 6, 7)     // Initialize all 4 elements with (5, 6, 7)
    Swag.assert(rgb[3].r == 5)
    Swag.assert(rgb[3].g == 6)
    Swag.assert(rgb[3].b == 7)

    Swag.init(rgb)(50, 60, 70)     // Reinitialize entire array with new values
    Swag.assert(rgb[3].r == 50)
    Swag.assert(rgb[3].g == 60)
    Swag.assert(rgb[3].b == 70)
}

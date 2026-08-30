#global private

/**
# Statement Termination in Swag

Unlike languages such as C or C++, there is no strict requirement to end statements
with a semicolon (';'). In Swag, a statement naturally terminates at the end of a line
('end of line'). This allows for cleaner, more concise syntax and reduces visual clutter,
making the code easier to read and maintain.
*/

#test
{
    // Declare two variables, 'x' and 'y', both of type 's32' (signed 32-bit integer),
    // and initialize them with the value '1'.
    var x, y: s32 = 1

    // Increment the value of both 'x' and 'y' by 1.
    x += 1
    y += 1

    // Use the 'Swag.assert' intrinsic to verify the correctness of the logic.
    Swag.assert(x == 2)     // Confirms that 'x' equals 2. Raises an error if it fails.
    Swag.assert(y == x)     // Confirms that 'y' equals 'x', which should also be 2.
}

/**
# Bodyless Declarations

Declarations without a body also terminate at the end of the line. Interface methods
and foreign functions do not need a special terminator.
*/

interface Counter
{
    mtd value()->u64
    mtd reset()
}

/**
# Semicolons

A trailing semicolon is accepted but redundant. Its useful role is to separate multiple
statements written on the same line. Use that compact form sparingly because it can make
control flow harder to scan.
*/

#test
{
    // Two variable declarations and initializations on a single line.
    var x = 0
    var y = 0

    // Increment both 'x' and 'y' on the same line.
    x += 1
    y += 1

    // Assert correctness of both variables.
    Swag.assert(x == 1)
    Swag.assert(y == 1)
}

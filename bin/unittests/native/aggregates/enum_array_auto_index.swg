#global private

enum Row { First, Second }
enum Column { Left, Right }

func identity(value: u32)->u32 => value

#test
{
    var values: [Row] u32
    values[.First] = 42
    values[.Second] = 7
    Swag.assert(values[.First] == 42)
    Swag.assert(identity(values[.Second]) == 7)

    var matrix: [Row, Column] u32
    matrix[.First, .Right] = 23
    matrix[.Second][.Left] = 19
    Swag.assert(matrix[.First, .Right] == 23)
    Swag.assert(identity(matrix[.Second][.Left]) == 19)

    var nested: [2] [Column] u32
    nested[1, .Right] = 31
    Swag.assert(nested[1, .Right] == 31)
}

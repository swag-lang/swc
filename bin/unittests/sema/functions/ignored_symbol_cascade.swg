#global fileprivate

enum Shape: u8
{
    Rock     = 1
    Paper    = 2
    Scissors = 3
}

interface IShapePicker
{
    mtd pick(opponent: Shape)->Shape;
}

struct Picker {}

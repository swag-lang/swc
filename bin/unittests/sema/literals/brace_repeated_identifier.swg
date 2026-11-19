#global private

struct Point { x, y: f32 }
struct Margins { Margin, other: f32 }
const Margin = 12.0'f32

func take(point: Point)->f32     => point.x + point.y
func take(margins: Margins)->f32 => margins.Margin + margins.other

const RepeatedValue: Point = {Margin, Margin}
#assert(RepeatedValue.x == Margin and RepeatedValue.y == Margin)

#test
{
    Swag.require(take({Margin, Margin}) == 2 * Margin)
}

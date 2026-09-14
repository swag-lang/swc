#global private

enum Preset { First, Second, Third }
var values: [Preset] u32

func initialize()
{
    var visits = 0
    for preset in Preset
    {
        visits += 1
        // Bound a broken loop so the regression fails instead of hanging.
        Swag.assert(visits <= 3)
        values[preset] = 42
    }
    Swag.assert(visits == 3)
}

#test
{
    initialize()
    Swag.assert(values[Preset.First] == 42)
    Swag.assert(values[Preset.Second] == 42)
    Swag.assert(values[Preset.Third] == 42)
}

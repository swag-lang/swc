#global private

const DegreesToRadians: f32 = 0.017453292519943295

func approxEqual(left: f32, right: f32)->bool
{
    return left >= right - 0.0001 and left <= right + 0.0001
}

struct LiteralAngle
{
    radians: f32
}

impl LiteralAngle
{
    #[Swag.ConstExpr, Swag.Implicit]
    mtd opSet(valueRadians: f32)
    {
        .radians = valueRadians
    }

    #[Swag.ConstExpr, Swag.Implicit]
    mtd(suffix: string) opSetLiteral(value: f32)
    {
        #if suffix == "deg" do
            .radians = value * DegreesToRadians
        #elif suffix == "rad" do
            .radians = value
        #else do
            #error("invalid angle suffix '" ++ suffix ++ "'")
    }
}

struct RotationCard
{
    angle: LiteralAngle
}

const RotationCards = [
    RotationCard{angle: 10.0'deg},
    RotationCard{angle: -12.0'deg},
    ]

#assert(RotationCards[0].angle.radians == 10.0'f32 * DegreesToRadians)
#assert(RotationCards[1].angle.radians == -12.0'f32 * DegreesToRadians)

#test
{
    let positive = RotationCard{angle: 10.0'deg}
    let negative = RotationCard{angle: -12.0'deg}

    @assert(approxEqual(positive.angle.radians, 10.0'f32 * DegreesToRadians))
    @assert(approxEqual(negative.angle.radians, -12.0'f32 * DegreesToRadians))
}

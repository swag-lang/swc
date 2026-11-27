#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math

// Integrates a diagonal edge across two adjacent pixels and a clipped row.
#test
{
    const Triangle: [3] Vector2 = [{0, 0}, {2, 0}, {0, 2}]
    var scratch: AreaScratch
    scratch.rasterize(Triangle, 2, 2)
    let upper = scratch.resolve(0, 2)
    Swag.require(upper.first == 0 and upper.end == 2)
    Swag.require(upper.values[0] == VerticalSamples and upper.values[1] == VerticalSamples * 0.5)
    let lower = scratch.resolve(1, 2)
    Swag.require(lower.first == 0 and lower.end == 1)
    Swag.require(lower.values[0] == VerticalSamples * 0.5)

    const Clipped: [3] Vector2 = [{-1, 0}, {2, 0}, {-1, 2}]
    scratch.rasterize(Clipped, 2, 2)
    let coverage = scratch.resolve(0, 2)
    Swag.require(Math.isEqualEpsilon(coverage.values[0], VerticalSamples * (11.0 / 12.0), 0.00001))

    const Wide: [3] Vector2 = [{0, 0}, {128, 0}, {0, 1}]
    scratch.rasterize(Wide, 128, 1)
    let wide = scratch.resolve(0, 128)
    Swag.require(wide.first == 0 and wide.end == 128)
    Swag.require(wide.values[0] == VerticalSamples * (255.0 / 256.0))
    Swag.require(wide.values[127] == VerticalSamples / 256.0)

    const Crossing: [4] Vector2 = [{0, 0}, {2, 2}, {2, 0}, {0, 2}]
    Swag.require(isSimpleAreaContour(Triangle))
    Swag.require(not isSimpleAreaContour(Crossing))
}

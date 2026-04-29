#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    @assert(rect.right() == 40)
    @assert(rect.bottom() == 60)
    @assert(rect.horzCenter() == 25)
    @assert(rect.vertCenter() == 40)

    let center = rect.center()
    @assert(center.x == 25 and center.y == 40)

    rect.setRight(45)
    rect.setBottom(70)
    @assert(rect.width == 35 and rect.height == 50)
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.moveLeft(5)
    rect.moveTop(10)
    rect.moveRight(7)
    rect.moveBottom(9)
    @assert(rect.x == 15 and rect.y == 30)
    @assert(rect.width == 32 and rect.height == 39)

    rect.offset(Math.Point{-5, -10})
    @assert(rect.x == 10 and rect.y == 20)

    rect.scale(2)
    @assert(rect.width == 64 and rect.height == 78)

    rect.inflate(1)
    @assert(rect.x == 9 and rect.y == 19)
    @assert(rect.width == 66 and rect.height == 80)
}

#test
{
    var rect = Math.Rectangle{}
    rect.set(Math.Point{30, 10}, Math.Point{10, 50})
    @assert(rect.x == 10 and rect.y == 10)
    @assert(rect.width == 20 and rect.height == 40)

    @assert(rect.contains(Math.Point{10, 10}))
    @assert(rect.contains(Math.Rectangle{12, 12, 4, 4}))
    @assert(!rect.contains(Math.Point{30, 50}))

    let clamped = rect.clampPoint(Math.Point{35, 5})
    @assert(clamped.x == 30 and clamped.y == 10)
    @assert(rect.distanceToPoint(Math.Point{30, 60}) == 10)
}

#test
{
    let a = Math.Rectangle{0, 0, 10, 10}
    let b = Math.Rectangle{5, -5, 10, 10}
    let intersection = Math.Rectangle.intersect(a, b)
    @assert(intersection == Math.Rectangle{5, 0, 5, 5})

    let mergedRect = Math.Rectangle.getUnion(a, b)
    @assert(mergedRect == Math.Rectangle{0, -5, 15, 15})
    @assert(a.intersectWith(b))
    @assert(!a.intersectWith(Math.Rectangle{20, 20, 1, 1}))
}

#test
{
    var rect = Math.Rectangle{10, 20, -30, -40}
    @assert(!rect.isNormalized())

    let normalized = rect.toNormalized()
    @assert(normalized == Math.Rectangle{-20, -20, 30, 40})

    rect.normalize()
    @assert(rect == normalized)
    @assert(rect.area() == 1200)
    @assert(rect.perimeter() == 140)
    @assert(rect.aspectRatio() == 0.75)
}

#test
{
    @assert(Math.Rectangle{0, 0, 0, 10}.isEmpty())
    @assert(Math.Rectangle{0, 0, 10, 0}.isEmpty())
    @assert(Math.Rectangle{0, 0, 0.00001, 10}.isEmptyEpsilon(0.001))
    @assert(Math.Rectangle{0, 0, 10, 0.00001}.isEmptyEpsilon(0.001))
    @assert(!Math.Rectangle{0, 0, 10, 10}.isEmptyEpsilon(0.001))
}

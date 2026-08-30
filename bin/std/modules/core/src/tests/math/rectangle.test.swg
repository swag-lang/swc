#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.assert(Math.Rectangle.Zero == Math.Rectangle{0, 0, 0, 0})
    Swag.assert((Math.Rectangle{1, 2, 3, 4} * 2.0) == Math.Rectangle{2, 4, 6, 8})

    var rect = Math.Rectangle{10, 20, 30, 40}
    Swag.assert(rect.right() == 40)
    Swag.assert(rect.bottom() == 60)
    Swag.assert(rect.horzCenter() == 25)
    Swag.assert(rect.vertCenter() == 40)
    Swag.assert(rect.center() == Math.Point{25, 40})
    Swag.assert(rect.topLeft() == Math.Point{10, 20})
    Swag.assert(rect.topRight() == Math.Point{40, 20})
    Swag.assert(rect.bottomLeft() == Math.Point{10, 60})
    Swag.assert(rect.bottomRight() == Math.Point{40, 60})
    Swag.assert(rect.size() == Math.Point{30, 40})
    Swag.assert(rect.isNormalized())

    rect.setRight(45)
    rect.setBottom(70)
    Swag.assert(rect == Math.Rectangle{10, 20, 35, 50})

    rect.setSize(Math.Point{12, 14})
    Swag.assert(rect == Math.Rectangle{10, 20, 12, 14})
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.moveLeft(5)
    Swag.assert(rect == Math.Rectangle{15, 20, 25, 40})

    rect.moveTop(10)
    Swag.assert(rect == Math.Rectangle{15, 30, 25, 30})

    rect.moveRight(7)
    Swag.assert(rect == Math.Rectangle{15, 30, 32, 30})

    rect.moveBottom(9)
    Swag.assert(rect == Math.Rectangle{15, 30, 32, 39})

    rect.offset(2)
    Swag.assert(rect == Math.Rectangle{17, 32, 32, 39})

    rect.offset(-7, -12)
    Swag.assert(rect == Math.Rectangle{10, 20, 32, 39})

    rect.offset(Math.Point{-5, -10})
    Swag.assert(rect == Math.Rectangle{5, 10, 32, 39})

    rect.clear()
    Swag.assert(rect.isZero())
    Swag.assert(rect == Math.Rectangle.Zero)
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.scale(2)
    Swag.assert(rect == Math.Rectangle{10, 20, 60, 80})

    rect.scale(0.5, 0.25)
    Swag.assert(rect == Math.Rectangle{10, 20, 30, 20})

    rect.inflate(1)
    Swag.assert(rect == Math.Rectangle{9, 19, 32, 22})

    rect.inflate(2, 3)
    Swag.assert(rect == Math.Rectangle{7, 16, 36, 28})

    rect.applyPadding(Math.Vector4{1, 2, 3, 4})
    Swag.assert(rect == Math.Rectangle{8, 18, 32, 22})
}

#test
{
    var rect = Math.Rectangle{}
    rect.set(Math.Point{30, 10}, Math.Point{10, 50})
    Swag.assert(rect == Math.Rectangle{10, 10, 20, 40})

    rect.set(Math.Point{10, 50}, Math.Point{30, 10})
    Swag.assert(rect == Math.Rectangle{10, 10, 20, 40})

    rect.set(Math.Point{30, 50}, Math.Point{10, 10})
    Swag.assert(rect == Math.Rectangle{10, 10, 20, 40})

    rect.set(Math.Point{-5, -5}, Math.Point{-5, -5})
    Swag.assert(rect == Math.Rectangle{-5, -5, 0, 0})

    rect = Math.Rectangle{10, 10, 20, 40}
    Swag.assert(rect.contains(10, 10))
    Swag.assert(rect.contains(29.999, 10))
    Swag.assert(rect.contains(10, 49.999))
    Swag.assert(rect.contains(Math.Point{29.999, 49.999}))
    Swag.assert(rect.contains(Math.Point{10, 49.999}))
    Swag.assert(!rect.contains(9.999, 10))
    Swag.assert(!rect.contains(10, 9.999))
    Swag.assert(!rect.contains(Math.Point{30, 50}))
    Swag.assert(!rect.contains(Math.Point{30, 10}))
    Swag.assert(!rect.contains(Math.Point{10, 50}))
    Swag.assert(rect.contains(Math.Rectangle{10, 10, 20, 40}))
    Swag.assert(rect.contains(Math.Rectangle{12, 12, 4, 4}))
    Swag.assert(rect.contains(Math.Rectangle{30, 50, 0, 0}))
    Swag.assert(!rect.contains(Math.Rectangle{9, 10, 1, 1}))
    Swag.assert(!rect.contains(Math.Rectangle{10, 9, 1, 1}))
    Swag.assert(!rect.contains(Math.Rectangle{29, 10, 2, 1}))
    Swag.assert(!rect.contains(Math.Rectangle{10, 49, 1, 2}))
    Swag.assert(!rect.contains(Math.Rectangle{12, 12, 40, 4}))

    Swag.assert(rect.clampPoint(Math.Point{20, 30}) == Math.Point{20, 30})
    Swag.assert(rect.clampPoint(Math.Point{35, 5}) == Math.Point{30, 10})
    Swag.assert(rect.clampPoint(Math.Point{5, 60}) == Math.Point{10, 50})
    Swag.assert(rect.distanceToPoint(Math.Point{20, 30}) == 0)
    Swag.assert(rect.distanceToPoint(Math.Point{30, 60}) == 10)
    Swag.assert(Math.isEqualEpsilon(rect.distanceToPoint(Math.Point{34, 53}), 5, 0.001))
}

#test
{
    let a = Math.Rectangle{0, 0, 10, 10}
    let b = Math.Rectangle{5, -5, 10, 10}
    Swag.assert(Math.Rectangle.intersect(a, b) == Math.Rectangle{5, 0, 5, 5})
    Swag.assert(Math.Rectangle.intersect(a, Math.Rectangle{2, 3, 4, 5}) == Math.Rectangle{2, 3, 4, 5})
    Swag.assert(Math.Rectangle.intersect(a, Math.Rectangle{-5, -5, 20, 20}) == a)
    Swag.assert(Math.Rectangle.intersect(a, Math.Rectangle{20, 20, 1, 1}) == Math.Rectangle.Zero)
    Swag.assert(Math.Rectangle.intersect(a, Math.Rectangle{10, 0, 5, 5}) == Math.Rectangle.Zero)
    Swag.assert(Math.Rectangle.intersect(a, Math.Rectangle{0, 10, 5, 5}) == Math.Rectangle.Zero)
    Swag.assert(a.intersects(b))
    Swag.assert(!a.intersects(Math.Rectangle{10, 0, 5, 5}))
    Swag.assert(!a.intersects(Math.Rectangle{0, 10, 5, 5}))

    var intersection = a
    intersection.intersect(b)
    Swag.assert(intersection == Math.Rectangle{5, 0, 5, 5})

    intersection = a
    intersection.intersect(Math.Rectangle{10, 0, 5, 5})
    Swag.assert(intersection == Math.Rectangle.Zero)

    Swag.assert(Math.Rectangle.combined(a, b) == Math.Rectangle{0, -5, 15, 15})
    Swag.assert(Math.Rectangle.combined(a, Math.Rectangle{2, 3, 4, 5}) == a)
    Swag.assert(Math.Rectangle.combined(a, Math.Rectangle{-5, -6, 2, 3}) == Math.Rectangle{-5, -6, 15, 16})
    Swag.assert(Math.Rectangle.combined(Math.Rectangle.Zero, Math.Rectangle{2, 3, 4, 5}) == Math.Rectangle{0, 0, 6, 8})

    var mergedRect = a
    mergedRect.combine(b)
    Swag.assert(mergedRect == Math.Rectangle{0, -5, 15, 15})
}

#test
{
    var rect = Math.Rectangle{10, 20, -30, -40}
    Swag.assert(!rect.isNormalized())
    Swag.assert(!rect.isEmpty())

    let normalized = rect.normalized()
    Swag.assert(normalized == Math.Rectangle{-20, -20, 30, 40})
    Swag.assert(!rect.isNormalized())

    rect.normalize()
    Swag.assert(rect == normalized)
    Swag.assert(rect.isNormalized())
    Swag.assert(rect.area() == 1200)
    Swag.assert(rect.perimeter() == 140)
    Swag.assert(rect.aspectRatio() == 0.75)
    Swag.assert(Math.Rectangle{0, 0, 10, 0}.aspectRatio() == 0)
    Swag.assert(Math.Rectangle{0, 0, 10, 20}.isNormalized())

    rect = Math.Rectangle{10, 20, -30, 40}
    rect.normalize()
    Swag.assert(rect == Math.Rectangle{-20, 20, 30, 40})

    rect = Math.Rectangle{10, 20, 30, -40}
    rect.normalize()
    Swag.assert(rect == Math.Rectangle{10, -20, 30, 40})
}

#test
{
    Swag.assert(Math.Rectangle{0, 0, 0, 10}.isEmpty())
    Swag.assert(Math.Rectangle{0, 0, 10, 0}.isEmpty())
    Swag.assert(!Math.Rectangle{0, 0, 10, 10}.isEmpty())
    Swag.assert(!Math.Rectangle{0, 0, -10, 10}.isEmpty())
    Swag.assert(!Math.Rectangle{0, 0, 10, -10}.isEmpty())
    Swag.assert(!Math.Rectangle{0, 0, -10, 10}.isNormalized())
    Swag.assert(!Math.Rectangle{0, 0, 10, -10}.isNormalized())
    Swag.assert(Math.Rectangle{0, 0, 0.00001, 10}.isEmptyEpsilon(0.001))
    Swag.assert(Math.Rectangle{0, 0, 10, 0.00001}.isEmptyEpsilon(0.001))
    Swag.assert(!Math.Rectangle{0, 0, 10, 10}.isEmptyEpsilon(0.001))
    Swag.assert(Math.Rectangle{0.00001, -0.00001, 0.00002, -0.00002}.isZeroEpsilon(0.001))
    Swag.assert(!Math.Rectangle{0, 0, 0.01, 0}.isZeroEpsilon(0.001))
    Swag.assert(Math.Rectangle{1, 2, 3, 4}.isEqualEpsilon(Math.Rectangle{1.00001, 1.99999, 3.00001, 3.99999}, 0.001))
    Swag.assert(!Math.Rectangle{1, 2, 3, 4}.isEqualEpsilon(Math.Rectangle{1.01, 2, 3, 4}, 0.001))
}

#test
{
    var rect = Math.Rectangle{1.25, -1.75, 2.5, -2.5}
    rect.round()
    Swag.assert(rect == Math.Rectangle{1, -2, 3, -3})

    rect = Math.Rectangle{1.75, -1.75, 2.75, -2.75}
    rect.trunc()
    Swag.assert(rect == Math.Rectangle{1, -1, 2, -2})

    rect = Math.Rectangle{1.25, -1.75, 2.25, -2.75}
    rect.ceil()
    Swag.assert(rect == Math.Rectangle{2, -1, 3, -2})
}

#test
{
    var rect = Math.Rectangle{0, 0, 200, 100}
    rect.fitWithin(Math.Rectangle{10, 20, 100, 100})
    Swag.assert(rect.isEqualEpsilon(Math.Rectangle{10, 45, 100, 50}, 0.001))

    let fitted = Math.Rectangle.fittedWithin(Math.Rectangle{0, 0, 100, 200}, Math.Rectangle{10, 20, 100, 100})
    Swag.assert(fitted.isEqualEpsilon(Math.Rectangle{35, 20, 50, 100}, 0.001))

    var empty = Math.Rectangle{1, 2, 0, 10}
    empty.fitWithin(Math.Rectangle{10, 20, 100, 100})
    Swag.assert(empty == Math.Rectangle{1, 2, 0, 10})

    empty = Math.Rectangle{1, 2, 10, 0}
    empty.fitWithin(Math.Rectangle{10, 20, 100, 100})
    Swag.assert(empty == Math.Rectangle{1, 2, 10, 0})
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.expandToInclude(Math.Point{20, 30})
    Swag.assert(rect == Math.Rectangle{10, 20, 30, 40})

    rect.expandToInclude(Math.Point{45, 15})
    Swag.assert(rect == Math.Rectangle{10, 15, 35, 45})

    rect.expandToInclude(Math.Point{5, 70})
    Swag.assert(rect == Math.Rectangle{5, 15, 40, 55})

    rect.expandToInclude(Math.Rectangle{-5, 10, 10, 15})
    Swag.assert(rect == Math.Rectangle{-5, 10, 50, 60})

    rect.expandToInclude(Math.Rectangle{20, 30, 40, 50})
    Swag.assert(rect == Math.Rectangle{-5, 10, 65, 70})
}

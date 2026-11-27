#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.Rectangle.Zero == {0, 0, 0, 0})
    Swag.require((Math.Rectangle{1, 2, 3, 4} * 2.0) == {2, 4, 6, 8})

    var scaled = Math.Rectangle{1, 2, 3, 4}
    scaled *= 2.0
    Swag.require(scaled == {2, 4, 6, 8})

    var rect = Math.Rectangle{10, 20, 30, 40}
    Swag.require(rect.right() == 40)
    Swag.require(rect.bottom() == 60)
    Swag.require(rect.horzCenter() == 25)
    Swag.require(rect.vertCenter() == 40)
    Swag.require(rect.center() == Math.Point{25, 40})
    Swag.require(rect.topLeft() == Math.Point{10, 20})
    Swag.require(rect.topRight() == Math.Point{40, 20})
    Swag.require(rect.bottomLeft() == Math.Point{10, 60})
    Swag.require(rect.bottomRight() == Math.Point{40, 60})
    Swag.require(rect.size() == Math.Point{30, 40})
    Swag.require(rect.isNormalized())

    rect.setRight(45)
    rect.setBottom(70)
    Swag.require(rect == {10, 20, 35, 50})

    rect.setSize({12, 14})
    Swag.require(rect == {10, 20, 12, 14})
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.moveLeft(5)
    Swag.require(rect == {15, 20, 25, 40})

    rect.moveTop(10)
    Swag.require(rect == {15, 30, 25, 30})

    rect.moveRight(7)
    Swag.require(rect == {15, 30, 32, 30})

    rect.moveBottom(9)
    Swag.require(rect == {15, 30, 32, 39})

    rect.offset(2)
    Swag.require(rect == {17, 32, 32, 39})

    rect.offset(-7, -12)
    Swag.require(rect == {10, 20, 32, 39})

    rect.offset({-5, -10})
    Swag.require(rect == {5, 10, 32, 39})

    rect.clear()
    Swag.require(rect.isZero())
    Swag.require(rect == Math.Rectangle.Zero)
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.scale(2)
    Swag.require(rect == {10, 20, 60, 80})

    rect.scale(0.5, 0.25)
    Swag.require(rect == {10, 20, 30, 20})

    rect.inflate(1)
    Swag.require(rect == {9, 19, 32, 22})

    rect.inflate(2, 3)
    Swag.require(rect == {7, 16, 36, 28})

    rect.applyPadding({1, 2, 3, 4})
    Swag.require(rect == {8, 18, 32, 22})
}

#test
{
    var rect = Math.Rectangle{}
    rect.set({30, 10}, {10, 50})
    Swag.require(rect == {10, 10, 20, 40})

    rect.set({10, 50}, {30, 10})
    Swag.require(rect == {10, 10, 20, 40})

    rect.set({30, 50}, {10, 10})
    Swag.require(rect == {10, 10, 20, 40})

    rect.set({-5, -5}, {-5, -5})
    Swag.require(rect == {-5, -5, 0, 0})

    rect = {10, 10, 20, 40}
    Swag.require(rect.contains(10, 10))
    Swag.require(rect.contains(29.999, 10))
    Swag.require(rect.contains(10, 49.999))
    Swag.require(rect.contains(Math.Point{29.999, 49.999}))
    Swag.require(rect.contains(Math.Point{10, 49.999}))
    Swag.require(not rect.contains(9.999, 10))
    Swag.require(not rect.contains(10, 9.999))
    Swag.require(not rect.contains(Math.Point{30, 50}))
    Swag.require(not rect.contains(Math.Point{30, 10}))
    Swag.require(not rect.contains(Math.Point{10, 50}))
    Swag.require(rect.contains({10, 10, 20, 40}))
    Swag.require(rect.contains({12, 12, 4, 4}))
    Swag.require(rect.contains({30, 50, 0, 0}))
    Swag.require(not rect.contains({9, 10, 1, 1}))
    Swag.require(not rect.contains({10, 9, 1, 1}))
    Swag.require(not rect.contains({29, 10, 2, 1}))
    Swag.require(not rect.contains({10, 49, 1, 2}))
    Swag.require(not rect.contains({12, 12, 40, 4}))

    Swag.require(rect.clampPoint({20, 30}) == Math.Point{20, 30})
    Swag.require(rect.clampPoint({35, 5}) == Math.Point{30, 10})
    Swag.require(rect.clampPoint({5, 60}) == Math.Point{10, 50})
    Swag.require(rect.distanceToPoint({20, 30}) == 0)
    Swag.require(rect.distanceToPoint({30, 60}) == 10)
    Swag.require(Math.isEqualEpsilon(rect.distanceToPoint({34, 53}), 5, 0.001))
}

#test
{
    let a = Math.Rectangle{0, 0, 10, 10}
    let b = Math.Rectangle{5, -5, 10, 10}
    Swag.require(Math.Rectangle.intersect(a, b) == {5, 0, 5, 5})
    Swag.require(Math.Rectangle.intersect(a, {2, 3, 4, 5}) == {2, 3, 4, 5})
    Swag.require(Math.Rectangle.intersect(a, {-5, -5, 20, 20}) == a)
    Swag.require(Math.Rectangle.intersect(a, {20, 20, 1, 1}) == Math.Rectangle.Zero)
    Swag.require(Math.Rectangle.intersect(a, {10, 0, 5, 5}) == Math.Rectangle.Zero)
    Swag.require(Math.Rectangle.intersect(a, {0, 10, 5, 5}) == Math.Rectangle.Zero)
    Swag.require(a.intersects(b))
    Swag.require(not a.intersects({10, 0, 5, 5}))
    Swag.require(not a.intersects({0, 10, 5, 5}))

    var intersection = a
    intersection.intersect(b)
    Swag.require(intersection == {5, 0, 5, 5})

    intersection = a
    intersection.intersect({10, 0, 5, 5})
    Swag.require(intersection == Math.Rectangle.Zero)

    Swag.require(Math.Rectangle.combined(a, b) == {0, -5, 15, 15})
    Swag.require(Math.Rectangle.combined(a, {2, 3, 4, 5}) == a)
    Swag.require(Math.Rectangle.combined(a, {-5, -6, 2, 3}) == {-5, -6, 15, 16})
    Swag.require(Math.Rectangle.combined(Math.Rectangle.Zero, {2, 3, 4, 5}) == {0, 0, 6, 8})

    var mergedRect = a
    mergedRect.combine(b)
    Swag.require(mergedRect == {0, -5, 15, 15})
}

#test
{
    var rect = Math.Rectangle{10, 20, -30, -40}
    Swag.require(not rect.isNormalized())
    Swag.require(not rect.isEmpty())

    let normalized = rect.normalized()
    Swag.require(normalized == {-20, -20, 30, 40})
    Swag.require(not rect.isNormalized())

    rect.normalize()
    Swag.require(rect == normalized)
    Swag.require(rect.isNormalized())
    Swag.require(rect.area() == 1200)
    Swag.require(rect.perimeter() == 140)
    Swag.require(rect.aspectRatio() == 0.75)
    Swag.require(Math.Rectangle{0, 0, 10, 0}.aspectRatio() == 0)
    Swag.require(Math.Rectangle{0, 0, 10, 20}.isNormalized())

    rect = {10, 20, -30, 40}
    rect.normalize()
    Swag.require(rect == {-20, 20, 30, 40})

    rect = {10, 20, 30, -40}
    rect.normalize()
    Swag.require(rect == {10, -20, 30, 40})
}

#test
{
    Swag.require(Math.Rectangle{0, 0, 0, 10}.isEmpty())
    Swag.require(Math.Rectangle{0, 0, 10, 0}.isEmpty())
    Swag.require(not Math.Rectangle{0, 0, 10, 10}.isEmpty())
    Swag.require(not Math.Rectangle{0, 0, -10, 10}.isEmpty())
    Swag.require(not Math.Rectangle{0, 0, 10, -10}.isEmpty())
    Swag.require(not Math.Rectangle{0, 0, -10, 10}.isNormalized())
    Swag.require(not Math.Rectangle{0, 0, 10, -10}.isNormalized())
    Swag.require(Math.Rectangle{0, 0, 0.00001, 10}.isEmptyEpsilon(0.001))
    Swag.require(Math.Rectangle{0, 0, 10, 0.00001}.isEmptyEpsilon(0.001))
    Swag.require(not Math.Rectangle{0, 0, 10, 10}.isEmptyEpsilon(0.001))
    Swag.require(Math.Rectangle{0.00001, -0.00001, 0.00002, -0.00002}.isZeroEpsilon(0.001))
    Swag.require(not Math.Rectangle{0, 0, 0.01, 0}.isZeroEpsilon(0.001))
    Swag.require(Math.Rectangle{1, 2, 3, 4}.isEqualEpsilon({1.00001, 1.99999, 3.00001, 3.99999}, 0.001))
    Swag.require(not Math.Rectangle{1, 2, 3, 4}.isEqualEpsilon({1.01, 2, 3, 4}, 0.001))
}

#test
{
    var rect = Math.Rectangle{1.25, -1.75, 2.5, -2.5}
    rect.round()
    Swag.require(rect == {1, -2, 3, -3})

    rect = {1.75, -1.75, 2.75, -2.75}
    rect.trunc()
    Swag.require(rect == {1, -1, 2, -2})

    rect = {1.25, -1.75, 2.25, -2.75}
    rect.ceil()
    Swag.require(rect == {2, -1, 3, -2})
}

#test
{
    var rect = Math.Rectangle{0, 0, 200, 100}
    rect.fitWithin({10, 20, 100, 100})
    Swag.require(rect.isEqualEpsilon({10, 45, 100, 50}, 0.001))

    let fitted = Math.Rectangle.fittedWithin({0, 0, 100, 200}, {10, 20, 100, 100})
    Swag.require(fitted.isEqualEpsilon({35, 20, 50, 100}, 0.001))

    var empty = Math.Rectangle{1, 2, 0, 10}
    empty.fitWithin({10, 20, 100, 100})
    Swag.require(empty == {1, 2, 0, 10})

    empty = {1, 2, 10, 0}
    empty.fitWithin({10, 20, 100, 100})
    Swag.require(empty == {1, 2, 10, 0})
}

#test
{
    var rect = Math.Rectangle{10, 20, 30, 40}
    rect.expandToInclude(Math.Point{20, 30})
    Swag.require(rect == {10, 20, 30, 40})

    rect.expandToInclude(Math.Point{45, 15})
    Swag.require(rect == {10, 15, 35, 45})

    rect.expandToInclude(Math.Point{5, 70})
    Swag.require(rect == {5, 15, 40, 55})

    rect.expandToInclude({-5, 10, 10, 15})
    Swag.require(rect == {-5, 10, 50, 60})

    rect.expandToInclude({20, 30, 40, 50})
    Swag.require(rect == {-5, 10, 65, 70})
}

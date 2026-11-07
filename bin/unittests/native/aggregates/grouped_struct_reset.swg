#global private

struct GroupedRect
{
    x, width: s32
}

struct GroupedItem
{
    body, arrow: GroupedRect
}

struct GroupedWideRect
{
    x, y, width, height: s32
}

struct GroupedWideItem
{
    body, arrow: GroupedWideRect
}

func resetGroupedRectangles()
{
    var items: [2] GroupedItem
    items[0].body  = {10, 20}
    items[0].arrow = {30, 40}
    items[1].body  = {50, 60}
    items[1].arrow = {70, 80}

    for &it in items
    {
        it.body, it.arrow = {}
    }

    for &it in items
    {
        Swag.require(it.body.x == 0)
        Swag.require(it.body.width == 0)
        Swag.require(it.arrow.x == 0)
        Swag.require(it.arrow.width == 0)
    }
}

func resetGroupedWideRectangles()
{
    var items: [2] GroupedWideItem
    for &it in items
    {
        it.body  = {1, 2, 3, 4}
        it.arrow = {5, 6, 7, 8}
        it.body, it.arrow = {}
        Swag.require(it.body.x == 0 and it.body.y == 0)
        Swag.require(it.body.width == 0 and it.body.height == 0)
        Swag.require(it.arrow.x == 0 and it.arrow.y == 0)
        Swag.require(it.arrow.width == 0 and it.arrow.height == 0)
    }
}

#test
{
    resetGroupedRectangles()
    resetGroupedWideRectangles()
}

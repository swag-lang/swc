#test
{
    var box = CrossFileAssignBox{value: 1}
    box += 2
    #assert(#typeof(box) == CrossFileAssignBox)
}

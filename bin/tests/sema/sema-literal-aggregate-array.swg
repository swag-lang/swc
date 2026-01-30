#global internal

const A = [1, 2, 3, 4, 5]
#print(#typeof(A))

const Af = [1.0, 2]
#print(#typeof(Af))

#test
{
    var x = 1
    var B = [x, 2, 3]
    #print(#typeof(B))

    var C = [x, 2, 3]

    var D = [1.0, 2] // int literal must be casted to float
    #print(#typeof(D))

    var E = []
    #print(#typeof(E))
}

#test
{
    var F = ["hello", 1] // swc-expected-error {{sema_err_cannot_cast}}
}
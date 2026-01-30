#global internal

const A = [1, 2, 3, 4, 5]
#print(#typeof(A))

#test
{
    var x = 1
    var B = [x, 2, 3]
    #print(#typeof(B))

    const C = [x, 2, 3] // swc-expected-error {{sema_err_expr_not_const}}
}
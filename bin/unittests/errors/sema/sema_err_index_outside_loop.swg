#global fileprivate

#test
{
    var value = @index // swc-expected-error {{sema_err_index_outside_loop}}
}

#test
{
    for 3
    {
        while true
        {
            var value = @index // swc-expected-error {{sema_err_index_outside_loop}}
            break
        }
    }
}

#global fileprivate

struct Node
{
    next: Node // swc-expected-error {{sema_err_struct_circular_reference}}
}

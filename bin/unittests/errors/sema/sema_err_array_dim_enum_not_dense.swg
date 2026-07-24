#global private

enum SparseArrayIndex
{
    First = 1
    Second
}

var values: [SparseArrayIndex] s32     // swc-expected-error {{sema_err_array_dim_enum_not_dense}}

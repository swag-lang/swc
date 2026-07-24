#global private

enum RowIndex
{
    First
    Second
}

enum ColumnIndex
{
    First
    Second
}

func readWrongIndex(values: const &[RowIndex] s32)->s32
{
    return values[ColumnIndex.First]     // swc-expected-error {{sema_err_index_enum_mismatch}}
}

#global private

// 'readonly' rides on a level instead of replacing one, so the level is written first.
struct Ordered
{
    readonly public value: s32     // swc-expected-error {{parser_err_readonly_before_access}}
}

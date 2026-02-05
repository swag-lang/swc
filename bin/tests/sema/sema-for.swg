#global internal

// Basic count loop
#test
{
    for 3
    {
        var x = 0
    }
}

// Named index in count loop
#test
{
    for i in 3
    {
        var x = i
    }
}

// Index variable scope
#test
{
    for #reverse i in 3
    {
        var x = i
    }

    var y = i // swc-expected-error {{sema_err_unknown_symbol}}
}

// Invalid modifier
#test
{
    for #bit i in 3 // swc-expected-error {{sema_err_modifier_unsupported}}
    {
    }
}

// Invalid count type (float)
#test
{
    for 1.5 // swc-expected-error {{sema_err_invalid_countof_type}}
    {
    }
}

// Invalid range type
#test
{
    for i in 0.0 to 1.5 // swc-expected-error {{sema_err_invalid_countof_type}}
    {
        var x = i
    }
}

// Invalid where clause
#test
{
    for i in 3 where s32 // swc-expected-error {{sema_err_not_value_expr}}
    {
        var x = i
    }
}

// Reverse iteration
#test
{
    for #reverse 5
    {
        var x = 0
    }
}

// Reverse with named index
#test
{
    for #reverse i in 5
    {
        var x = i
    }
}

// Infinite loop
#test
{
    for
    {
        break
    }
}

// Infinite loop with do syntax
#test
{
    for
    {
        break
    }
}

// Range-based 'to' (inclusive)
#test
{
    for i in 1 to 5
    {
        var x = i
    }
}

// Range-based 'until' (exclusive)
#test
{
    for i in 1 until 5
    {
        var x = i
    }
}

// Range with reverse
#test
{
    for #reverse i in 1 to 5
    {
        var x = i
    }
}

// Range until with reverse
#test
{
    for #reverse i in 1 until 5
    {
        var x = i
    }
}

// Where clause with count loop
#test
{
    for i in 10 where i > 3
    {
        var x = i
    }
}

// Where clause with range loop
#test
{
    for i in 0 to 10 where i % 2 == 0
    {
        var x = i
    }
}

// Where clause with range until loop
#test
{
    for i in 0 until 10 where i > 5
    {
        var x = i
    }
}

// Where clause with reverse
#test
{
    for #reverse i in 10 where i < 5
    {
        var x = i
    }
}

// Nested for loops
#test
{
    for i in 3
    {
        for j in 3
        {
            var x = i
            var y = j
        }
    }
}

// Nested scope isolation
#test
{
    for i in 1
    {
        for j in 1
        {
            var x = j
        }
        var y = j // swc-expected-error {{sema_err_unknown_symbol}}
    }
}

// For with break statement
#test
{
    for 10
    {
        var x = 0
        break
    }
}

// For with continue statement
#test
{
    for i in 10
    {
        var x = i
        continue
        var y = 0 // Unreachable code is allowed
    }
}

// Nested break affects only inner loop
#test
{
    for 2
    {
        for 2
        {
            break
        }
        var x = 0
    }
}

// For with array type
#test
{
    var arr: [5]s32 = [1, 2, 3, 4, 5]
    for arr
    {
        var x = 0
    }
}

// For with array named index
#test
{
    var arr: [3]s32 = [1, 2, 3]
    for i in arr
    {
        var x = i
    }
}

// Empty for block (with count)
#test
{
    for 3
    {
    }
}

// Empty for block (with range)
#test
{
    for i in 0 to 3
    {
    }
}

// For with single statement (no braces)
#test
{
    for 3 do
        var x = 0
}

// For with range single statement
#test
{
    for i in 3 do
        var x = i
}

// Variable declared in for indexoccupies scope
#test
{
    for i in 1
    {
    }

    for i in 1
    {
    }
}

// Index variable can shadow outer variable
#test
{
    var i = 5
    for i in 3
    {
        var x = i // shadows outer i
    }
}

// Where clause variable access - check context
#test
{
    for i in 5 where i > 0
    {
        var x = i
    }
}

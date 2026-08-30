#global namespace Tool

using Core

/*
A command line being assembled, in the order the program reads it.

A tool spends most of its code naming compiler arguments, so naming them has to cost one line:

    var arguments: Arguments
    arguments.add(["build", "--workspace", context.workspacePath("std").toString()])

The tokens are owned, because most of them are built rather than written down — a path joined, a
configuration chosen. Pass `string`, and this keeps the copy.
*/
public struct Arguments
{
    values: Array'String
}

public impl Arguments
{
    // Appends every token, in the order given.
    mtd add(tokens: const [..] string)
    {
        .values.reserve((.values).count + tokens.count)
        for token in tokens do
            .values.add(String.from(token))
    }

    // Appends every token of `other`.
    mtd addAll(other: Arguments)
    {
        for value in other.values do
            .values.add(value)
    }

    // Returns the tokens, for whoever starts the process.
    mtd const toSlice()->const [..] String => .values.toSlice()

    // Returns how many tokens have been named so far.
    mtd const count()->u64 => (.values).count
}

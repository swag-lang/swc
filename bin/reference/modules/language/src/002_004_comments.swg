#global private

/**
# Line and Block Comments

'//' starts a comment that ends at the next line break. It can occupy its own
line or follow code. '/*' starts a block comment, and the matching '*/' ends it;
a block comment may span lines or separate tokens within an expression.

Comments are ignored as program text. Delimiters inside a string literal are
ordinary characters, so a URL does not start a comment.
*/

#test
{
    // A line comment may precede a statement.
    let answer = 40 /* a block comment between tokens */ + 2
    Swag.assert(answer == 42)     // A trailing comment belongs to this line.

    let address = "https://example.com"
    Swag.assert(address.count == 19)
}

/**
# Nested Block Comments

Block comments nest. Every inner '/*' must have a matching '*/' before the
outer comment can end. This allows temporarily commenting out code that already
contains block comments.
*/

#test
{
    /*
        let disabled = 1
        /* This inner comment ends without ending the outer one. */
        disabled += 1
    */
    Swag.assert(true)
}

/**
# Comments as Native Documentation

Ordinary '//' comments also document declarations when 'swc doc' generates an
API reference. No special '///' prefix or '@param' tags are needed. Put the
comment immediately before the declaration, or after a field or enum value
on the same line.

'//!' opts source-file prose into the module's **File documentation** section.
The numbered examples mode used by this reference renders '/** ... */' blocks
as prose and the surrounding code as examples.

See [Native documentation](#_002_011_native_documentation_swg) for placement,
Markdown, symbol links, module guides, and generation commands.
*/

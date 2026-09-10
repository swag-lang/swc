#global private

/**
# Documentation Is Part of the Source

'swc doc' parses and type-checks a module, then renders its documentation as
static HTML. It uses ordinary comments for API contracts and Markdown for longer
guides. Documentation comments do not change visibility or runtime behavior.

| Content | Where to write it |
|---|---|
| Module purpose, conventions, and first use | Leading comment in 'module.swg' |
| One declaration's contract | '//' immediately before the declaration |
| Short field or enum-case description | '//' after the member on the same line |
| Source-file overview | Lines beginning with '//!' in that source file |
| Longer workflow or tutorial | Markdown files in 'help/' beside 'src/' |
| Executable chapter | Numbered '.swg' file in '.Examples' mode |

# Documenting a Declaration with '//'

Start with one short, complete summary line. The generated index uses that line
on its own. Separate further detail with an empty '//' line. Name the units,
accepted ranges, failure behavior, ownership, and lifetime when they are part of
the contract; avoid merely repeating the signature.

Put documentation before the first attribute so it describes the declaration
as a whole. Block comments are accepted too, but '//' is sufficient for both
short summaries and multi-paragraph contracts.
*/

// Returns the larger of two non-negative byte counts.
//
// Equal counts return the same value. This operation allocates no storage.
#[Swag.ConstExpr]
func largerByteCount(left, right: u64)->u64 => Swag.max(left, right)

#test
{
    #assert(largerByteCount(12, 8) == 12)
    Swag.assert(largerByteCount(8, 8) == 8)
}

/**
These declarations are private examples. In a reusable API source file, write
'#global export' for a uniformly exported surface, or use the visibility required
by each declaration. Public visibility and documentation are separate decisions:
a comment does not publish a private declaration.

# Fields, Enum Cases, and Methods

Use trailing comments for short member contracts. Put a longer explanation above
the member when it needs paragraphs, a table, or an example. Named aggregate
members default to 'internal', so group intended public fields explicitly.
*/

// Describes a region of a larger byte sequence.
struct ByteRegion
{
    public
    {
        offset: u64     // Byte offset from the start of the sequence.
        count:  u64     // Number of bytes in the region; zero denotes an empty region.
    }
}

impl ByteRegion
{
    // Reports whether the region contains no bytes.
    mtd const isEmpty()->bool => me.count == 0
}

// Selects how an existing destination is handled.
enum DestinationPolicy
{
    Keep        // Preserve existing contents.
    Replace     // Replace existing contents with the new value.
}

#test
{
    let region = ByteRegion{offset: 16, count: 0}
    Swag.assert(region.isEmpty())
    Swag.assert(region.offset == 16)
}

/**
Document an interface method at its interface declaration. Implementations do
not need to repeat that shared contract. Put the common description on the first
overload; document later overloads when their behavior differs.

# Module Overviews and Guides

The overview is the first comment in 'module.swg', before imports and '#run'.
Keep it focused on what the module provides and how a caller starts using it.
For example, a separate module could contain:

```swag
// Reads and writes framed byte messages.
//
// Readers borrow their input buffer. Keep it alive until reading finishes.
#run
{
    let cfg = Swag.compiler().getBuildCfg()!
    cfg.genDoc.kind         = .Api
    cfg.genDoc.titleContent = "Message API"
    cfg.genDoc.outputName   = "messages"
}
```

Put longer guides under 'help/', beside 'src/'. The generator includes '.md'
files in lexical path order in the API page. Begin each guide with one '# Title';
it becomes the guide title and its table-of-contents entry. Number filenames
when the reading order matters, such as '001_getting_started.md' and
'002_streaming.md'.

# File Documentation with '//!'

Mark every line of a file overview with '//!', including blank paragraph
separators. The generator removes the marker and renders the remaining Markdown
once in the module-wide **File documentation** section, under the source filename.
Separate marked blocks in the same file become separate paragraphs.

```swag
//! Message sizes count payload bytes, excluding the header.
//!
//! A reader borrows its input and never releases that storage.

// Returns the payload length in bytes.
func payloadLength()->u64 => 0
```

The '//!' lines do not become the function's description, even when placed next
to it. Ordinary '//' comments stay with declarations. Licence and provenance
headers do not implicitly become module prose.

# Markdown in Comments

Write ordinary Markdown after the comment prefix. Supported forms include
headings, paragraphs, emphasis, inline code, fenced 'swag' examples, links,
images, tables, lists, description lists, and callouts.

```swag
// Reads one message from the input.
//
// The input must contain a complete header.
//
// - Lengths count bytes.
// - The returned view borrows the input.
//   Keep the input alive while using the result.
//
// > NOTE: An empty payload is a valid message.
```

- Use '- ' for unordered list items and '1. ', '2. ', and so on for ordered lists.
  Indent continuation lines to the item's text column and nested items two
  spaces further. Leave a blank comment line after a list before normal prose.
- Reserve '+ ' for a description-list term, with its description indented below.
- Use backticks around code tokens and 'swag' as the language of a code fence.
- Introduce callouts with '> NOTE:', '> TIP:', '> WARNING:', '> ATTENTION:',
  or '> EXAMPLE:'.
- Describe parameters and return values in prose; '@param', '@return', and
  '@throws' are not documentation tags.

# Linking to Symbols

In API comments and guides, write a qualified symbol as `[[Swag.TypeInfo]]` or
`[[Core.Math.Vector2]]`. The generator resolves types, functions, methods,
constants, fields, and enum cases, including symbols from other modules.
Use the full name when an unqualified name could be ambiguous.

Put literal link syntax inside inline or fenced code when explaining it, as
this chapter does. Use ordinary Markdown links for documentation pages; generated
pages use '.html' URLs. Declarations and field tables receive type links
automatically when the target is known.

# Choosing What Appears

API mode documents the public surface. '#[Swag.NoDoc]' excludes a declaration
that must remain public but is intentionally outside the reader-facing reference.
It does not change visibility, linkage, or the exported API. Use it for a deliberate
exclusion, not as a replacement for a missing contract.

'#[Swag.Opaque]' hides a struct's representation from consumers and from generated
field documentation. Its public type and operations still need documentation.

# Choosing a Documentation Mode

Set 'Swag.BuildCfg.genDoc.kind' in 'module.swg':

| Kind | Source organization | Result |
|---|---|---|
| '.Api' | Public declarations, module overview, '//!', and Markdown guides | One module API page |
| '.Examples' | Numbered source files such as '001_000_introduction.swg' and '001_001_first_steps.swg' | One guided document with a chapter index |
| '.Pages' | Individual source files | One page per source file |

In '.Examples' mode, '/** ... */' blocks contain prose and executable Swag stays
outside those blocks. 'NNN_000_title.swg' starts a chapter, and other 'NNN_MMM'
files are its sections. Filenames determine presentation order, never execution
order. A fenced snippet inside a prose block is illustrative text; it is not
compiled or executed. Put runnable checks in '#test' blocks outside the prose.

# Generating and Checking the Result

For a workspace containing a module named 'messages':

```text
swc doc -w path/to/workspace -m messages --doc-output-dir path/to/docs
swc test -w path/to/workspace -m messages
```

'doc' checks the source and renders pages; 'test' executes the examples. One does
not replace the other. The documentation command also generates the public runtime
API page. 'genDoc.outputName' sets the module page's base name, while
'genDoc.titleContent' sets its displayed title.

Open the generated HTML and check the module overview, chapter or symbol index,
code blocks, lists, tables, callouts, and links. An API review should also confirm
that all intended public declarations appear and that private or deliberately
excluded declarations do not.
*/

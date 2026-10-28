#global public
#global namespace Lens

using Core

// Selects which sources answer a query, from the character the query starts with.
//
// The foot of the lens teaches the prefixes its sources answer: `:` a line, `/` the files,
// `>` the commands.
enum Prefix
{
    None       // No prefix: every source answers.
    Line       // `:` — lines and positions of what the window shows.
    File       // `/` — files to open.
    Action     // `>` — the commands of the application, and nothing else.
}

// Returns the character that selects `prefix`, or an empty string for [[Gui.Lens.Prefix.None]].
func prefixText(prefix: Prefix)->string
{
    switch #complete prefix
    {
    case .None:   return ""
    case .Line:   return ":"
    case .File:   return "/"
    case .Action: return ">"
    }
}

// Returns the prefix `query` starts with, and what the reader typed after it.
func splitPrefix(query: string)->{prefix: Prefix, rest: string}
{
    if query.count == 0 do
        return {.None, query}
    let rest = Swag.makeString(query.buffer + 1, query.count - 1)
    switch query[0]
    {
    case ':': return {.Line, rest}
    case '/': return {.File, rest}
    case '>': return {.Action, rest}
    default:  return {.None, query}
    }
}

// One row of the lens: a command, a file, a line, a symbol.
//
// A row is chosen with the keys or the pointer. Choosing it closes the lens, then runs `run`
// when it is set, and posts the command `id` to the owner of the lens otherwise.
struct Entry
{
    public
    {
        title:      String          // Words of the row; the characters the query matched are highlighted.
        detail:     String          // Faint reading at the end of the row: a line, a path, a shortcut.
        lead:       String          // Mono reading leading the row, such as a line number; shown instead of the glyph.
        glyph:      Icon            // Glyph leading the row when it has no lead reading.
        monoTitle:  bool            // Whether the title is code or a measure, set in the fixed-width face.
        monoDetail: bool            // Whether the detail is a measure or a shortcut, set in the fixed-width face.
        disabled:   bool            // Whether the row is shown faint and cannot be chosen.
        checked:    bool            // Whether the row is the choice or the setting in force, marked with a check in Arc.
        id:         WndId?          // Command posted to the owner of the lens when the row is chosen; borrowed for the life of the row.
        run:        (func||())?     // Action run when the row is chosen, once the lens has left the screen.
        spans:      Array'Span      // Runs of the title the query matched; the lens fills it when a source leaves it empty.
    }

    score: s32     // How well the query answered the title; the lens ranks the rows by it.
}

// A picture in the strip of a section: a recent document, a page.
//
// Choosing it with the pointer closes the lens, then runs `run`.
struct Picture
{
    public
    {
        title: String                                     // What the picture shows, said when the pointer rests on it.
        paint: (func||(*Painter, Math.Rectangle))?        // Paints the picture into its cell, in local coordinates.
        run:   (func||())?                                // Action run when the picture is chosen, once the lens has left the screen.
    }
}

// A group of rows under one section label.
//
// A group can also hold a strip of pictures after its rows, such as the recent documents of an
// application, ended by a link to where every one of them is, such as "Library →".
struct Section
{
    public
    {
        label:    String            // Words of the section label, written in small spaced capitals.
        count:    u32               // Number written after the label, as in "In this file · 5"; zero writes none.
        entries:  Array'Entry       // Rows of the group, in the order their source gave them.
        pictures: Array'Picture     // Pictures of the strip after the rows, in reading order.
        link:     String            // Words of the link ending the strip; empty for none.
        linkRun:  (func||())?       // Action run when the link is chosen, once the lens has left the screen.
    }

    order:  Array'u64     // Rows the lens shows, by index into `entries`, in the order it shows them.
    best:   s32           // Score of the best row shown.
    ranked: bool          // Whether the lens ranks the rows, as it does the commands of a family.
}

impl Section
{
    // Appends a row titled `title` and returns it, to be filled further.
    //
    // The pointer stays valid until the next row is added to this section.
    #[Swag.Discardable]
    mtd addEntry(title: string)->*Entry
    {
        let result = .entries.emplaceInitAddress()
        result.title = title
        return result
    }

    // Appends a picture to the strip of the section and returns it, to be filled further.
    //
    // The pointer stays valid until the next picture is added to this section.
    #[Swag.Discardable]
    mtd addPicture(title: string)->*Picture
    {
        let result = .pictures.emplaceInitAddress()
        result.title = title
        return result
    }

    // Ends the strip of pictures with a link: `text`, such as "Library →", runs `run` when chosen.
    mtd setLink(text: string, run: func||())
    {
        .link    = text
        .linkRun = run
    }

    // Reports whether the section shows anything: a row or a picture.
    mtd const isEmpty()->bool => .entries.isEmpty() and .pictures.isEmpty()
}

// Collects the answers of every source to one query.
//
// The lens builds one for each query, hands it to every source that answers the prefix, then
// shows its sections in the order they were added.
struct Results
{
    public
    {
        readonly
        {
            query:    String     // What the reader typed, without its prefix.
            prefix:   Prefix     // Prefix the reader typed, or [[Gui.Lens.Prefix.None]].
            sections: ArrayPtr'Section     // Groups of rows, in the order they show.
        }
    }
}

impl Results
{
    // Appends a section labelled `label` and returns it, to be filled with rows.
    //
    // The pointer stays valid as long as these results. `count` is written after the label; zero
    // writes none.
    #[Swag.Discardable]
    mtd addSection(label: string, count: u32 = 0)->*Section
    {
        let result = .sections.addNew()
        result.label = label
        result.count = count
        return result
    }

    // Returns the number of rows of every section.
    mtd const entryCount()->u64
    {
        var result = 0'u64
        for section in .sections do
            result += section!.entries.count
        return result
    }

    internal mtd reset(query: string, prefix: Prefix)
    {
        .query  = query
        .prefix = prefix
        .sections.clear()
    }
}

// A source of rows: answers the query `results` holds by adding sections to it.
alias Provider = func||(*Results)

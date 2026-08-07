#pragma once

#include "Doc/DocTypes.h"

#include <span>

SWC_BEGIN_NAMESPACE();

// One row of the index a page carries for its own search box. A page indexes what it
// renders and nothing else, so it stays a single file that reaches no network.
struct DocSearchEntry
{
    Utf8 name;
    Utf8 anchor;
    Utf8 detail;
    char kind = 'f';
};

class DocSearch
{
public:
    static char kindLetter(DocItemKind kind);
    static Utf8 summarize(std::string_view markdown);
    static void collectHeadings(std::vector<DocSearchEntry>& outEntries, std::string_view html);
    static Utf8 script(const DocPageOptions& options, std::span<const DocSearchEntry> entries);
};

SWC_END_NAMESPACE();

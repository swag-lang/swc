#pragma once

#include "Doc/DocSearch.h"

SWC_BEGIN_NAMESPACE();

// What a page is made of: its rail, its article, and the index its own search box reads.
// A page without a rail is a single-page document, and shows its article alone.
struct DocPageContent
{
    std::string_view                toc;
    std::string_view                article;
    std::span<const DocSearchEntry> searchEntries;
    bool                            singlePage = false;
};

class DocPage
{
public:
    static Utf8 styles();
    static Utf8 construct(const DocPageOptions& options, const DocPageContent& content);
};

SWC_END_NAMESPACE();

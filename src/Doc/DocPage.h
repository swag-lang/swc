#pragma once

#include "Doc/DocTypes.h"

SWC_BEGIN_NAMESPACE();

class DocPage
{
public:
    static Utf8 styles();
    static Utf8 construct(const DocPageOptions& options, std::string_view toc, std::string_view content, bool pages);
};

SWC_END_NAMESPACE();

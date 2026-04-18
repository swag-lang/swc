#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceView;

namespace Format
{
    struct Context
    {
        const Ast*         ast     = nullptr;
        const SourceView*  srcView = nullptr;
        const Options*     options = nullptr;
        Utf8               output;
    };

    class AstSourceWriter
    {
    public:
        static void write(Context& formatCtx);
    };
}

SWC_END_NAMESPACE();

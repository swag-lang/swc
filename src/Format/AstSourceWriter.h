#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceFile;
class SourceView;
class TaskContext;

namespace Format
{
    struct Context
    {
        TaskContext*       task    = nullptr;
        const SourceFile*  file    = nullptr;
        const Ast*         ast     = nullptr;
        const SourceView*  srcView = nullptr;
        const Options*     options = nullptr;
        Utf8               output;
    };

    class AstSourceWriter
    {
    public:
        static Result write(Context& formatCtx);
    };
}

SWC_END_NAMESPACE();

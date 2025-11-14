#pragma once

SWC_BEGIN_NAMESPACE()

class CompilerInstance;

namespace CompilerCommand
{
    Result syntax(const CompilerInstance& compiler);
    Result format(const CompilerInstance& compiler);
}

SWC_END_NAMESPACE()

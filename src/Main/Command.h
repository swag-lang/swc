#pragma once

SWC_BEGIN_NAMESPACE()

class CompilerInstance;

namespace Command
{
    void syntax(CompilerInstance& compiler);
    void format(CompilerInstance& compiler);
    void sema(CompilerInstance& compiler);
}

SWC_END_NAMESPACE()

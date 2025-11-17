#pragma once

SWC_BEGIN_NAMESPACE()

class CompilerInstance;

namespace Command
{
    void syntax(CompilerInstance& compiler);
    void format(CompilerInstance& compiler);
    void build(CompilerInstance& compiler);
}

SWC_END_NAMESPACE()

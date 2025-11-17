#pragma once

SWC_BEGIN_NAMESPACE()

class CompilerInstance;

namespace Command
{
    void syntax(const CompilerInstance& compiler);
    void format(const CompilerInstance& compiler);
    void build(const CompilerInstance& compiler);
}

SWC_END_NAMESPACE()

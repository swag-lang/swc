#pragma once

SWC_BEGIN_NAMESPACE();
class Sema;
struct AstNode;
struct SourceCodeRange;

namespace ConstantHelpers
{
    ConstantRef makeSourceCodeLocation(Sema& sema, const AstNode& node);
    ConstantRef makeSourceCodeLocation(Sema& sema, const SourceCodeRange& codeRange);
}

SWC_END_NAMESPACE();

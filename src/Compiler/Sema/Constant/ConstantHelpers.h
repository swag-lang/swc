#pragma once

SWC_BEGIN_NAMESPACE();
class Sema;
struct AstNode;

namespace ConstantHelpers
{
    ConstantRef makeSourceCodeLocation(Sema& sema, const AstNode& node);
}

SWC_END_NAMESPACE();

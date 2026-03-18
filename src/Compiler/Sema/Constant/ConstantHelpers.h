#pragma once

SWC_BEGIN_NAMESPACE();
class Sema;
class SymbolFunction;
struct AstNode;
struct SourceCodeRange;

namespace ConstantHelpers
{
    ConstantRef materializeStaticPayloadConstant(Sema& sema, TypeRef typeRef, ByteSpan payload);
    ConstantRef makeSourceCodeLocation(Sema& sema, const AstNode& node, const SymbolFunction* function = nullptr);
    ConstantRef makeSourceCodeLocation(Sema& sema, const SourceCodeRange& codeRange, const SymbolFunction* function = nullptr);
}

SWC_END_NAMESPACE();

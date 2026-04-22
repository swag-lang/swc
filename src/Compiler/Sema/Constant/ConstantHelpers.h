#pragma once

SWC_BEGIN_NAMESPACE();
class Sema;
class SymbolFunction;
struct AstNode;
struct SourceCodeRange;

namespace ConstantHelpers
{
    Result      waitStaticPayloadTypeReady(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef);
    ConstantRef materializeStaticPayloadConstant(Sema& sema, TypeRef typeRef, ByteSpan payload);
    Result      makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const AstNode& node, const SymbolFunction* function = nullptr);
    Result      makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const SourceCodeRange& codeRange, const SymbolFunction* function = nullptr);
}

SWC_END_NAMESPACE();

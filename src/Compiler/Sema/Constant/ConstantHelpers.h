#pragma once
#include <span>

#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();
class Sema;
struct SemaNodeView;
class SymbolFunction;
struct AstNode;
struct SourceCodeRange;

namespace ConstantHelpers
{
    Result      waitStaticPayloadTypeReady(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef);
    uint64_t    materializeConstantStorageAndGetAddress(Sema& sema, const SemaNodeView& view);
    ConstantRef materializeStaticPayloadConstant(Sema& sema, TypeRef typeRef, std::span<const std::byte> payload);
    Result      makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const AstNode& node, const SymbolFunction* function = nullptr);
    Result      makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const SourceCodeRange& codeRange, const SymbolFunction* function = nullptr);
}

SWC_END_NAMESPACE();

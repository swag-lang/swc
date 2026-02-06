#pragma once
#include <cstddef>
#include <vector>

#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class TypeInfo;

namespace ConstantOps
{
    Result extractStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef);
    Result extractAtIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef);
    bool   lowerToBytes(Sema& sema, ConstantRef cstRef, TypeRef dstTypeRef, std::byte* dst, uint64_t dstSize);
    bool   lowerAggregateStructToBytes(Sema& sema, const std::vector<ConstantRef>& values, const TypeInfo& dstType, std::byte* dst, uint64_t dstSize);
}

SWC_END_NAMESPACE();

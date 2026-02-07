#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class TypeInfo;

namespace ConstantHelpers
{
    Result      extractStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef);
    Result      extractAtIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef);
    bool        lowerToBytes(Sema& sema, ByteSpan dst, ConstantRef cstRef, TypeRef dstTypeRef);
    bool        lowerAggregateArrayToBytes(Sema& sema, ByteSpan dst, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    bool        lowerAggregateStructToBytes(Sema& sema, ByteSpan dst, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    ConstantRef makeConstantLocation(Sema& sema, const AstNode& node);
}

SWC_END_NAMESPACE();

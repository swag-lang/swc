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
    void        lowerToBytes(Sema& sema, ByteSpan dstBytes, ConstantRef cstRef, TypeRef dstTypeRef);
    bool        lowerAggregateArrayToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    void        lowerAggregateStructToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    ConstantRef makeDefaultStruct(Sema& sema, TypeRef typeRef);
    ConstantRef makeConstantLocation(Sema& sema, const AstNode& node);
}

SWC_END_NAMESPACE();

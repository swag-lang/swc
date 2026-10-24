#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;
class SymbolStruct;

// 'u is .Circle': the union tested and the case it is tested against.
struct TaggedIsPayload
{
    const SymbolStruct* tagged  = nullptr;
    ConstantRef         caseRef = ConstantRef::invalid();
};

class SymbolStruct;
class SymbolVariable;
class TaskContext;

// A tagged union ('union(Kind)') keeps its tag at offset 0 and one active member after it. These
// helpers answer the questions every site asks about it: which union a type is, which case a value
// holds, and whether the flow proves the case a payload access needs.
namespace SemaTagged
{
    // The tagged union a value of this type is, through aliases.
    const SymbolStruct* unionOf(TaskContext& ctx, TypeRef typeRef);
    // The same, also through one pointer or reference ('me', a borrowed parameter).
    const SymbolStruct* unionOfPointee(TaskContext& ctx, TypeRef typeRef);
    // The tagged union declaring a payload member, or null for any other field.
    const SymbolStruct* ownerUnion(const SymbolVariable& member);

    uint64_t    valueBits(TaskContext& ctx, ConstantRef value);
    Utf8        caseName(Sema& sema, const SymbolStruct& tagged, ConstantRef value);
    Utf8        caseShortName(Sema& sema, const SymbolStruct& tagged, ConstantRef value);
    ConstantRef caseFromBits(Sema& sema, const SymbolStruct& tagged, uint64_t bits);

    // A use reads the tag type and the case table, both settled once the union is complete.
    Result waitUnion(Sema& sema, const SymbolStruct& tagged);

    // The tagged union the innermost binding type expects ('u = .Circle'), with that type.
    Result contextUnion(Sema& sema, const SymbolStruct*& outTagged, TypeRef& outUnionTypeRef);
    // The tag value named 'idRef'; invalid when the tag declares no such value.
    Result findCase(Sema& sema, ConstantRef& outCaseRef, const SymbolStruct& tagged, IdentifierRef idRef);

    std::span<ConstantRef> copyCases(Sema& sema, std::span<const ConstantRef> values);
    std::span<ConstantRef> complementCases(Sema& sema, const SymbolStruct& tagged, std::span<const ConstantRef> values);
    std::span<ConstantRef> unionCases(Sema& sema, std::span<const ConstantRef> lhs, std::span<const ConstantRef> rhs);

    // The access path of the union reached from 'leftRef', which is the union itself, a pointer to
    // it, or a struct holding it through 'using' fields.
    bool extractUnionPath(Sema& sema, AstNodeRef leftRef, TypeRef leftTypeRef, const SymbolStruct& tagged, SmallVector4<const Symbol*>& outPath);
    // When 'exprRef' reads the tag of a tagged union path ('Swag.kindOf(u)'), that union.
    const SymbolStruct* kindOfSubject(Sema& sema, AstNodeRef exprRef, SmallVector4<const Symbol*>& outPath);

    // After 'u = .Circle{...}' the flow knows the case; after any other assignment it knows nothing.
    void noteAssignedCase(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef);

    // A payload member is read or written only where the flow proves its case, or under '!'.
    Result checkPayloadAccess(Sema& sema, AstNodeRef accessRef, AstNodeRef leftRef, TypeRef leftTypeRef, const SymbolVariable& member);
    // The postfix '!' over a payload access: asserted when unproven, rejected when already proven.
    Result checkCaseAssertion(Sema& sema, AstNodeRef childRef, bool& outHandled);

    // The case of the union stored 'offset' bytes into a constant.
    ConstantRef readConstantCase(Sema& sema, const SymbolStruct& tagged, ConstantRef cstRef, uint64_t offset = 0);
    Result      makeCaseConstant(Sema& sema, ConstantRef& outCstRef, TypeRef unionTypeRef, ConstantRef tagCstRef, ConstantRef payloadCstRef);
}

SWC_END_NAMESPACE();

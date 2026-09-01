#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct SwitchCaseCodeGenPayload
    {
        MicroLabelRef testLabel     = MicroLabelRef::invalid();
        MicroLabelRef bodyLabel     = MicroLabelRef::invalid();
        MicroLabelRef nextTestLabel = MicroLabelRef::invalid();
        MicroLabelRef nextBodyLabel = MicroLabelRef::invalid();
        AstNodeRef    nextCaseRef   = AstNodeRef::invalid();
        bool          hasNextCase   = false;
    };

    struct SwitchStmtCodeGenPayload
    {
        MicroLabelRef                                            doneLabel          = MicroLabelRef::invalid();
        MicroLabelRef                                            noMatchLabel       = MicroLabelRef::invalid();
        TypeRef                                                  compareTypeRef     = TypeRef::invalid();
        CodeGenNodePayload                                       switchValuePayload = {};
        MicroReg                                                 switchValueReg;
        MicroReg                                                 dynamicSourceTypeReg;
        MicroReg                                                 dynamicSourcePtrReg;
        MicroOpBits                                              compareOpBits       = MicroOpBits::B64;
        SymbolFunction*                                          stringCmpFunction   = nullptr;
        SymbolFunction*                                          dynamicAsFunction   = nullptr;
        SymbolFunction*                                          dynamicIsFunction   = nullptr;
        bool                                                     hasExpression       = false;
        bool                                                     useStringCompare    = false;
        bool                                                     useTypeInfoCompare  = false;
        bool                                                     useUnsignedCond     = false;
        bool                                                     dynamicStructSwitch = false;
        bool                                                     isAnySwitch         = false;
        bool                                                     dispatchOwnsTests   = false;
        std::unordered_map<AstNodeRef, SwitchCaseCodeGenPayload> caseStates;
    };

    SwitchStmtCodeGenPayload* switchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<SwitchStmtCodeGenPayload>(nodeRef);
    }

    SwitchStmtCodeGenPayload& setSwitchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const SwitchStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseSwitchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        SwitchStmtCodeGenPayload* payload = switchStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    MicroOpBits switchCompareOpBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        if (typeInfo.isFloat())
        {
            uint32_t bits = typeInfo.payloadFloatBits();
            if (!bits)
                bits = static_cast<uint32_t>(typeInfo.sizeOf(ctx) * 8);
            if (!bits)
                bits = 64;
            return microOpBitsFromBitWidth(bits);
        }

        return CodeGenTypeHelpers::conditionBits(typeInfo, ctx);
    }

    using CodeGenMemoryHelpers::loadOperandToRegister;

    void emitConditionTrueJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroLabelRef trueLabel)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits condBits = CodeGenTypeHelpers::compareBits(typeInfo, codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualRegisterForType(typeRef);

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress())
            builder.emitLoadRegMem(condReg, payload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, payload.reg, condBits);

        CodeGenCompareHelpers::emitCompareRegZero(codeGen, condReg, typeInfo, condBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen, typeInfo, CodeGenCompareHelpers::truthyCondition(typeInfo), trueLabel);
    }

    SymbolFunction* runtimeStringCompareFunction(CodeGen& codeGen)
    {
        const IdentifierRef idRef = codeGen.idMgr().predefined(IdentifierManager::PredefinedName::RuntimeStringCmp);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    SymbolFunction* runtimeDynamicAsFunction(CodeGen& codeGen)
    {
        const IdentifierRef idRef = codeGen.idMgr().predefined(IdentifierManager::PredefinedName::RuntimeAs);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    SymbolFunction* runtimeDynamicIsFunction(CodeGen& codeGen)
    {
        const IdentifierRef idRef = codeGen.idMgr().predefined(IdentifierManager::PredefinedName::RuntimeIs);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    bool isDynamicStructSwitchType(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef   unwrappedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), typeRef);
        const TypeInfo& typeInfo         = codeGen.typeMgr().get(unwrappedTypeRef);
        return typeInfo.isInterface() || typeInfo.isAny();
    }

    Result emitDynamicStructSwitchCaseTests(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, AstNodeRef caseRef, MicroLabelRef successLabel, MicroLabelRef failLabel)
    {
        const auto* casePayload = codeGen.sema().semaPayload<DynamicStructSwitchCasePayload>(caseRef);
        SWC_ASSERT(casePayload != nullptr);

        MicroBuilder&         builder   = codeGen.builder();
        const SymbolFunction* runtimeFn = switchState.dynamicAsFunction;
        if (!runtimeFn)
            runtimeFn = runtimeDynamicAsFunction(codeGen);

        SWC_ASSERT(runtimeFn != nullptr);
        if (!runtimeFn)
            return Result::Error;

        const SymbolFunction* runtimeIsFn = switchState.dynamicIsFunction;
        if (!runtimeIsFn)
            runtimeIsFn = runtimeDynamicIsFunction(codeGen);

        SWC_ASSERT(runtimeIsFn != nullptr);
        if (!runtimeIsFn)
            return Result::Error;

        if (casePayload->bindingSymbol != nullptr)
        {
            SWC_ASSERT(casePayload->expressions.size() == 1);

            MicroReg      targetTypeReg       = MicroReg::invalid();
            const TypeRef targetStructTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), codeGen.viewType(casePayload->expressions.front().typeExprRef).typeRef());
            SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(targetTypeReg, codeGen, targetStructTypeRef));

            const MicroReg args[]    = {targetTypeReg, switchState.dynamicSourceTypeReg, switchState.dynamicSourcePtrReg};
            const MicroReg resultReg = codeGen.nextVirtualIntRegister();
            SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, *runtimeFn, args, resultReg));
            builder.emitCmpRegImm(resultReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, failLabel);

            CodeGenNodePayload boundPayload;
            boundPayload.typeRef = casePayload->bindingSymbol->typeRef();
            boundPayload.reg     = resultReg;

            const TypeInfo& bindingType = codeGen.typeMgr().get(boundPayload.typeRef);
            if (bindingType.isAnyPointer() || bindingType.isReference() || bindingType.isMoveReference())
                boundPayload.setIsValue();
            else
                boundPayload.setIsAddress();

            codeGen.setVariablePayload(*casePayload->bindingSymbol, boundPayload);

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, successLabel);
            return Result::Continue;
        }

        for (const auto& expr : casePayload->expressions)
        {
            MicroReg      targetTypeReg       = MicroReg::invalid();
            const TypeRef targetStructTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), codeGen.viewType(expr.typeExprRef).typeRef());
            SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(targetTypeReg, codeGen, targetStructTypeRef));

            const MicroReg args[]    = {targetTypeReg, switchState.dynamicSourceTypeReg};
            const MicroReg resultReg = codeGen.nextVirtualIntRegister();
            SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, *runtimeIsFn, args, resultReg));
            builder.emitCmpRegImm(resultReg, ApInt(0, 64), MicroOpBits::B8);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, successLabel);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, failLabel);
        return Result::Continue;
    }

    bool isDynamicStructSwitchCaseTarget(CodeGen& codeGen, AstNodeRef switchRef, AstNodeRef caseRef)
    {
        const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
        if (!switchState || !switchState->dynamicStructSwitch)
            return false;

        const auto& caseNode = codeGen.node(caseRef).cast<AstSwitchCaseStmt>();
        return caseNode.spanExprRef.isValid();
    }

    // The bytes a case compares against, when the case is a string the compiler already knows.
    std::optional<std::string_view> knownCaseText(CodeGen& codeGen, AstNodeRef caseExprRef)
    {
        if (caseExprRef.isInvalid())
            return std::nullopt;

        const SemaNodeView caseView = codeGen.viewConstant(caseExprRef);
        if (caseView.cstRef().isInvalid())
            return std::nullopt;

        const ConstantValue& constantValue = codeGen.cstMgr().get(caseView.cstRef());
        if (!constantValue.isString())
            return std::nullopt;

        return constantValue.getString();
    }

    // One read of a known string, at the width the comparison uses.
    struct StringCompareChunk
    {
        size_t      offset = 0;
        size_t      width  = 0;
        MicroOpBits opBits = MicroOpBits::B8;
    };

    // The reads that cover a string of `length` bytes end to end without ever stepping outside it:
    // whole chunks from the start, then one last chunk overlapping the previous one when the length
    // is not a multiple of the chunk width. That is how a small memcmp is written, and it is why a
    // name of eight bytes or less costs two comparisons whatever its length.
    void appendStringCompareChunks(SmallVector<StringCompareChunk>& chunks, size_t length)
    {
        if (!length)
            return;

        size_t width = 1;
        if (length >= 8)
            width = 8;
        else if (length >= 4)
            width = 4;
        else if (length >= 2)
            width = 2;

        const MicroOpBits opBits = microOpBitsFromChunkSize(static_cast<uint32_t>(width));
        for (size_t offset = 0; offset + width <= length; offset += width)
            chunks.push_back({.offset = offset, .width = width, .opBits = opBits});

        if (chunks.back().offset + width < length)
            chunks.push_back({.offset = length - width, .width = width, .opBits = opBits});
    }

    uint64_t stringChunkValue(std::string_view text, const StringCompareChunk& chunk)
    {
        uint64_t value = 0;
        for (size_t index = 0; index < chunk.width; ++index)
            value |= static_cast<uint64_t>(static_cast<uint8_t>(text[chunk.offset + index])) << (index * 8);
        return value;
    }

    // Compares the chunks of the switch value against the same chunks of a known string, jumping to
    // `failLabel` at the first difference. `provenMask` names the chunks an enclosing test already
    // matched, which is why a search that split the group on one chunk does not read it again. An
    // eight-byte chunk never fits an instruction's immediate; the legalizer is what gives it a
    // register, so the shape stays the same at every width.
    void emitStringChunksCompare(CodeGen& codeGen, MicroReg dataReg, std::string_view text, std::span<const StringCompareChunk> chunks, uint32_t provenMask, MicroLabelRef failLabel)
    {
        MicroBuilder& builder = codeGen.builder();
        for (size_t index = 0; index < chunks.size(); ++index)
        {
            if (provenMask & (1u << index))
                continue;

            const StringCompareChunk& chunk    = chunks[index];
            const MicroReg            chunkReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(chunkReg, dataReg, chunk.offset, chunk.opBits);
            builder.emitCmpRegImm(chunkReg, ApInt(stringChunkValue(text, chunk), 64), chunk.opBits);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, failLabel);
        }
    }

    void emitKnownBytesCompare(CodeGen& codeGen, MicroReg dataReg, std::string_view text, MicroLabelRef failLabel)
    {
        SmallVector<StringCompareChunk> chunks;
        appendStringCompareChunks(chunks, text.size());
        emitStringChunksCompare(codeGen, dataReg, text, chunks.span(), 0, failLabel);
    }

    // Compares the switch value against one case without calling anything, when the case is a
    // string the compiler knows and short enough to read in two chunks.
    //
    // A `switch` over strings used to be a chain of calls, one per case, which made a lookup table
    // written as a hundred cases cost a hundred calls. The length is one load and rejects nearly
    // every case on its own; the bytes that follow are compared in place.
    bool emitKnownStringCompareEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, AstNodeRef caseExprRef, MicroLabelRef successLabel)
    {
        constexpr size_t MaxInlineLength = 16;

        const std::optional<std::string_view> caseText = knownCaseText(codeGen, caseExprRef);
        if (!caseText.has_value() || caseText->size() > MaxInlineLength)
            return false;
        if (!switchState.switchValuePayload.reg.isValid())
            return false;

        MicroBuilder&       builder   = codeGen.builder();
        const MicroLabelRef failLabel = builder.createLabel();
        const MicroReg      lengthReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(lengthReg, switchState.switchValuePayload.reg, offsetof(Runtime::String, length), MicroOpBits::B64);
        builder.emitCmpRegImm(lengthReg, ApInt(caseText->size(), 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, failLabel);

        if (!caseText->empty())
        {
            const MicroReg dataReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(dataReg, switchState.switchValuePayload.reg, offsetof(Runtime::String, ptr), MicroOpBits::B64);
            emitKnownBytesCompare(codeGen, dataReg, *caseText, failLabel);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, successLabel);
        builder.placeLabel(failLabel);
        return true;
    }

    Result emitStringCompareEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const CodeGenNodePayload& casePayload, MicroLabelRef successLabel)
    {
        SymbolFunction* stringCmpSymbol = switchState.stringCmpFunction;
        if (!stringCmpSymbol)
            stringCmpSymbol = runtimeStringCompareFunction(codeGen);

        SWC_ASSERT(stringCmpSymbol != nullptr);
        if (!stringCmpSymbol)
            return Result::Error;

        codeGen.function().addCallDependency(stringCmpSymbol);

        auto&                             stringCmpFunction = *stringCmpSymbol;
        const CallConvKind                callConvKind      = stringCmpFunction.callConvKind();
        const CallConv&                   callConv          = CallConv::get(callConvKind);
        const auto&                       params            = stringCmpFunction.parameters();
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        SWC_ASSERT(params.size() >= 2);
        SWC_ASSERT(params[0] != nullptr);
        SWC_ASSERT(params[1] != nullptr);
        CodeGenCallHelpers::appendPreparedValueArg(preparedArgs, codeGen, callConv, switchState.switchValuePayload, params[0]->typeRef());
        CodeGenCallHelpers::appendPreparedValueArg(preparedArgs, codeGen, callConv, casePayload, params[1]->typeRef());

        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (stringCmpFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &stringCmpFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &stringCmpFunction, preparedCall);

        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, stringCmpFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);
        SWC_ASSERT(normalizedRet.numBits == 8);

        const MicroReg compareReg = codeGen.nextVirtualIntRegister();
        ABICall::materializeReturnToReg(builder, compareReg, callConvKind, normalizedRet);
        builder.emitCmpRegImm(compareReg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, successLabel);
        return Result::Continue;
    }

    // 'case T' matches the same types as 'value == T', so a type switch compares runtime
    // identity instead of the descriptor addresses a plain register compare would look at.
    Result emitTypeInfoCompareEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const CodeGenNodePayload& casePayload, MicroLabelRef successLabel)
    {
        MicroReg caseReg = MicroReg::invalid();
        loadOperandToRegister(caseReg, codeGen, casePayload, switchState.compareTypeRef, switchState.compareOpBits);

        MicroBuilder&       builder        = codeGen.builder();
        const MicroLabelRef otherTypeLabel = builder.createLabel();
        CodeGenCompareHelpers::emitTypeInfoEqualJump(codeGen, switchState.switchValueReg, caseReg, successLabel, otherTypeLabel);
        builder.placeLabel(otherTypeLabel);
        return Result::Continue;
    }

    Result emitSwitchValueEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, AstNodeRef caseExprRef, MicroLabelRef successLabel)
    {
        const CodeGenNodePayload& casePayload = codeGen.payload(caseExprRef);
        if (switchState.useStringCompare)
        {
            if (emitKnownStringCompareEqualsJump(codeGen, switchState, caseExprRef, successLabel))
                return Result::Continue;
            return emitStringCompareEqualsJump(codeGen, switchState, casePayload, successLabel);
        }

        if (switchState.useTypeInfoCompare)
            return emitTypeInfoCompareEqualsJump(codeGen, switchState, casePayload, successLabel);

        MicroReg caseReg = MicroReg::invalid();
        loadOperandToRegister(caseReg, codeGen, casePayload, switchState.compareTypeRef, switchState.compareOpBits);

        MicroBuilder& builder = codeGen.builder();
        builder.emitCmpRegReg(switchState.switchValueReg, caseReg, switchState.compareOpBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen, codeGen.typeMgr().get(switchState.compareTypeRef), {.primaryCond = MicroCond::Equal, .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::RequireOrdered}, successLabel);
        return Result::Continue;
    }

    void emitSwitchRangeFailJumps(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const AstRangeExpr& rangeExpr, MicroLabelRef failLabel)
    {
        const bool      unsignedOrFloat = switchState.useUnsignedCond;
        const TypeInfo& compareType     = codeGen.typeMgr().get(switchState.compareTypeRef);

        if (rangeExpr.nodeExprDownRef.isValid())
        {
            const CodeGenNodePayload& lowerPayload = codeGen.payload(rangeExpr.nodeExprDownRef);
            MicroReg                  lowerReg     = MicroReg::invalid();
            loadOperandToRegister(lowerReg, codeGen, lowerPayload, switchState.compareTypeRef, switchState.compareOpBits);

            codeGen.builder().emitCmpRegReg(switchState.switchValueReg, lowerReg, switchState.compareOpBits);
            CodeGenCompareHelpers::emitConditionJump(codeGen, compareType, {.primaryCond = CodeGenCompareHelpers::lessCond(unsignedOrFloat), .floatUnorderedMode = compareType.isFloat() ? CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered : CodeGenCompareHelpers::FloatUnorderedMode::ExcludedByPrimary}, failLabel);
        }

        if (rangeExpr.nodeExprUpRef.isValid())
        {
            const CodeGenNodePayload& upperPayload = codeGen.payload(rangeExpr.nodeExprUpRef);
            MicroReg                  upperReg     = MicroReg::invalid();
            loadOperandToRegister(upperReg, codeGen, upperPayload, switchState.compareTypeRef, switchState.compareOpBits);

            codeGen.builder().emitCmpRegReg(switchState.switchValueReg, upperReg, switchState.compareOpBits);
            const MicroCond failCond = rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive) ? CodeGenCompareHelpers::greaterCond(unsignedOrFloat) : CodeGenCompareHelpers::greaterEqualCond(unsignedOrFloat);
            CodeGenCompareHelpers::emitConditionJump(codeGen, compareType, {.primaryCond = failCond, .floatUnorderedMode = compareType.isFloat() ? CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered : CodeGenCompareHelpers::FloatUnorderedMode::ExcludedByPrimary}, failLabel);
        }
    }

    bool caseBodyEndsWithFallthrough(CodeGen& codeGen, const AstSwitchCaseStmt& node)
    {
        SmallVector<AstNodeRef>  statements;
        const AstSwitchCaseBody& caseBody = codeGen.node(node.nodeBodyRef).cast<AstSwitchCaseBody>();
        codeGen.ast().appendNodes(statements, caseBody.spanChildrenRef);
        if (statements.empty())
            return false;

        return codeGen.node(statements.back()).is(AstNodeId::FallThroughStmt);
    }

    SmallVector<AstNodeRef> collectSwitchCaseRefs(CodeGen& codeGen, const AstSwitchStmt& switchNode)
    {
        SmallVector<AstNodeRef> caseRefs;
        if (switchNode.spanChildrenRef.isValid())
            codeGen.ast().appendNodes(caseRefs, switchNode.spanChildrenRef);
        return caseRefs;
    }

    SmallVector<AstNodeRef> collectSwitchCaseExprRefs(CodeGen& codeGen, const AstSwitchCaseStmt& caseNode)
    {
        SmallVector<AstNodeRef> caseExprRefs;
        if (caseNode.spanExprRef.isValid())
            codeGen.ast().appendNodes(caseExprRefs, caseNode.spanExprRef);
        return caseExprRefs;
    }

    // ---------------------------------------------------------------------------------------------
    // Dispatching a switch on its value
    //
    // Testing one case after another costs a comparison per case, and a switch written as a lookup
    // table has a hundred of them. When the compiler knows what every case tests, it can answer the
    // same question with one search over those values, emitted before the first case and jumping
    // straight to the body that matches.
    // ---------------------------------------------------------------------------------------------

    // A string longer than this keeps the runtime call: comparing it in place costs one instruction
    // per eight bytes, and a case list of such strings is code the switch rarely reaches.
    constexpr size_t K_MAX_DISPATCH_STRING_LENGTH = 64;

    // One target of a dispatch: the interval of values that selects it, and where control goes.
    struct SwitchDispatchEntry
    {
        uint64_t      lowKey  = 0;
        uint64_t      highKey = 0;
        MicroLabelRef label   = MicroLabelRef::invalid();
    };

    bool switchDispatchKeyLess(uint64_t left, uint64_t right, bool useUnsignedCond)
    {
        if (useUnsignedCond)
            return left < right;
        return static_cast<int64_t>(left) < static_cast<int64_t>(right);
    }

    // A key is compared at the width of the switch value, so it is carried in the form that width
    // gives it: sign-extended to sixty-four bits when the comparison is signed, so that sorting the
    // keys here orders them the way the emitted comparisons will.
    uint64_t switchDispatchKey(uint64_t rawValue, MicroOpBits opBits, bool useUnsignedCond)
    {
        const uint64_t mask = getBitsMask(opBits);
        rawValue &= mask;
        const uint64_t signBit = mask ^ (mask >> 1);
        if (!useUnsignedCond && (rawValue & signBit))
            rawValue |= ~mask;
        return rawValue;
    }

    // Emits the search that sends a value to its target. The intervals must be sorted and disjoint,
    // which is what lets the search ignore the order the cases were written in: below a handful of
    // targets a straight chain is smaller and just as fast, above it a binary search turns N
    // comparisons into log2(N). Every path out of the search ends in a jump, so what follows it is
    // only ever reached through a label.
    struct SwitchDispatchSearch
    {
        static constexpr size_t K_MAX_CHAIN_ENTRIES = 8;
        static constexpr size_t K_MIN_JUMP_TABLE_ENTRIES = 32;
        static constexpr size_t K_MAX_JUMP_TABLE_ENTRIES = 240;

        CodeGen*      codeGen         = nullptr;
        MicroReg      valueReg        = MicroReg::invalid();
        MicroOpBits   opBits          = MicroOpBits::B64;
        bool          useUnsignedCond = false;
        bool          allowJumpTable  = false;
        MicroLabelRef defaultLabel    = MicroLabelRef::invalid();

        void emitCompare(uint64_t key) const
        {
            codeGen->builder().emitCmpRegImm(valueReg, ApInt(key & getBitsMask(opBits), 64), opBits);
        }

        void emitJump(MicroCond cond, MicroLabelRef label) const
        {
            codeGen->builder().emitJumpToLabel(cond, MicroOpBits::B32, label);
        }

        void emitLeaf(const SwitchDispatchEntry& entry) const
        {
            emitCompare(entry.lowKey);
            if (entry.lowKey == entry.highKey)
            {
                emitJump(MicroCond::Equal, entry.label);
            }
            else
            {
                emitJump(CodeGenCompareHelpers::lessCond(useUnsignedCond), defaultLabel);
                emitCompare(entry.highKey);
                emitJump(CodeGenCompareHelpers::lessEqualCond(useUnsignedCond), entry.label);
            }

            emitJump(MicroCond::Unconditional, defaultLabel);
        }

        void emitChain(std::span<const SwitchDispatchEntry> entries) const
        {
            MicroBuilder& builder = codeGen->builder();
            for (const SwitchDispatchEntry& entry : entries)
            {
                emitCompare(entry.lowKey);
                if (entry.lowKey == entry.highKey)
                {
                    emitJump(MicroCond::Equal, entry.label);
                    continue;
                }

                const MicroLabelRef nextLabel = builder.createLabel();
                emitJump(CodeGenCompareHelpers::lessCond(useUnsignedCond), nextLabel);
                emitCompare(entry.highKey);
                emitJump(CodeGenCompareHelpers::lessEqualCond(useUnsignedCond), entry.label);
                builder.placeLabel(nextLabel);
            }

            emitJump(MicroCond::Unconditional, defaultLabel);
        }

        bool tryEmitJumpTable(std::span<const SwitchDispatchEntry> entries) const
        {
            if (!allowJumpTable || entries.size() < K_MIN_JUMP_TABLE_ENTRIES)
                return false;

            const uint64_t tableSize = entries.back().highKey - entries.front().lowKey + 1;
            if (!tableSize || tableSize > K_MAX_JUMP_TABLE_ENTRIES)
                return false;

            uint64_t coveredValues = 0;
            for (const SwitchDispatchEntry& entry : entries)
                coveredValues += entry.highKey - entry.lowKey + 1;
            if (coveredValues * 2 < tableSize)
                return false;

            SmallVector<MicroLabelRef> tableTargets;
            tableTargets.resize(static_cast<size_t>(tableSize), defaultLabel);
            const uint64_t tableLowKey = entries.front().lowKey;
            for (const SwitchDispatchEntry& entry : entries)
            {
                const uint64_t intervalSize = entry.highKey - entry.lowKey + 1;
                const uint64_t tableOffset  = entry.lowKey - tableLowKey;
                for (uint64_t index = 0; index < intervalSize; ++index)
                    tableTargets[static_cast<size_t>(tableOffset + index)] = entry.label;
            }

            SmallVector<MicroLabelRef> successorLabels;
            successorLabels.reserve(tableTargets.size());
            for (const MicroLabelRef label : tableTargets)
            {
                if (std::ranges::find(successorLabels, label) == successorLabels.end())
                    successorLabels.push_back(label);
            }

            MicroBuilder& builder  = codeGen->builder();
            const MicroReg indexReg = codeGen->nextVirtualIntRegister();
            if (opBits == MicroOpBits::B64)
                builder.emitLoadRegReg(indexReg, valueReg, MicroOpBits::B64);
            else if (useUnsignedCond)
                builder.emitLoadZeroExtendRegReg(indexReg, valueReg, MicroOpBits::B64, opBits);
            else
                builder.emitLoadSignedExtendRegReg(indexReg, valueReg, MicroOpBits::B64, opBits);

            if (tableLowKey)
                builder.emitOpBinaryRegImm(indexReg, ApInt(tableLowKey, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitCmpRegImm(indexReg, ApInt(tableSize - 1, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Above, MicroOpBits::B32, defaultLabel);

            const MicroLabelRef tableLabel = builder.createLabel();
            const MicroReg      tableReg   = codeGen->nextVirtualIntRegister();
            const MicroReg      targetReg  = codeGen->nextVirtualIntRegister();
            builder.emitLoadLabelAddress(tableReg, tableLabel);
            builder.emitLoadAmcRegMem(targetReg, MicroOpBits::B32, tableReg, indexReg, sizeof(uint32_t), 0, MicroOpBits::B64);
            builder.emitLoadSignedExtendRegReg(targetReg, targetReg, MicroOpBits::B64, MicroOpBits::B32);
            builder.emitOpBinaryRegReg(targetReg, tableReg, MicroOp::Add, MicroOpBits::B64);
            builder.emitJumpReg(targetReg, successorLabels.span());
            builder.placeLabel(tableLabel);
            builder.emitJumpTableData(tableTargets.span());
            return true;
        }

        void emit(std::span<const SwitchDispatchEntry> entries) const
        {
            if (tryEmitJumpTable(entries))
                return;

            if (entries.size() == 1)
            {
                emitLeaf(entries.front());
                return;
            }

            if (entries.size() <= K_MAX_CHAIN_ENTRIES)
            {
                emitChain(entries);
                return;
            }

            // Split on the lowest key of the upper half: a value below it can only match below it.
            const size_t        middle     = entries.size() / 2;
            const MicroLabelRef lowerLabel = codeGen->builder().createLabel();
            emitCompare(entries[middle].lowKey);
            emitJump(CodeGenCompareHelpers::lessCond(useUnsignedCond), lowerLabel);
            emit(entries.subspan(middle));
            codeGen->builder().placeLabel(lowerLabel);
            emit(entries.first(middle));
        }
    };

    MicroLabelRef switchCaseBodyLabel(const SwitchStmtCodeGenPayload& switchState, AstNodeRef caseRef)
    {
        const auto itCase = switchState.caseStates.find(caseRef);
        SWC_ASSERT(itCase != switchState.caseStates.end());
        return itCase->second.bodyLabel;
    }

    struct SwitchStringCase
    {
        std::string_view text;
        MicroLabelRef    bodyLabel = MicroLabelRef::invalid();
    };

    // Collects every string the cases test, with the body each one selects. A switch qualifies only
    // when the compiler knows all of them: one case that has to be evaluated where it stands would
    // have to be tested in source order, which is exactly what the dispatch gives up.
    bool collectStringSwitchCases(SmallVector<SwitchStringCase>& cases, CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, std::span<const AstNodeRef> caseRefs)
    {
        for (const AstNodeRef caseRef : caseRefs)
        {
            const auto&         caseNode     = codeGen.node(caseRef).cast<AstSwitchCaseStmt>();
            const MicroLabelRef bodyLabel    = switchCaseBodyLabel(switchState, caseRef);
            const auto          caseExprRefs = collectSwitchCaseExprRefs(codeGen, caseNode);
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                const std::optional<std::string_view> caseText = knownCaseText(codeGen, caseExprRef);
                if (!caseText.has_value() || caseText->size() > K_MAX_DISPATCH_STRING_LENGTH)
                    return false;
                cases.push_back({.text = *caseText, .bodyLabel = bodyLabel});
            }
        }

        return !cases.empty();
    }

    // How many different values the cases of a group show at one chunk. A chunk that gives every case
    // its own value is the best split there is; one they all share is no split at all.
    size_t countDistinctChunkValues(std::span<const SwitchStringCase> cases, const StringCompareChunk& chunk)
    {
        SmallVector<uint64_t> values;
        values.reserve(cases.size());
        for (const SwitchStringCase& stringCase : cases)
        {
            const uint64_t value = stringChunkValue(stringCase.text, chunk);
            if (std::ranges::find(values, value) == values.end())
                values.push_back(value);
        }

        return values.size();
    }

    // Emits the cases of one length group, separating them on the chunk that tells the most of them
    // apart - the first eight bytes when the names differ there, a later chunk when they share a
    // prefix, and so on down. What one chunk leaves together the next one splits, and the chunks
    // cover the whole string, so two cases can only survive them all by testing the same string.
    //
    // This is what answers a group whose names are all the same length: the length said nothing, and
    // the search over one chunk still costs log2 of the group rather than one comparison per case.
    void emitStringGroupCases(CodeGen& codeGen, MicroReg dataReg, std::span<const SwitchStringCase> cases, std::span<const StringCompareChunk> chunks, uint32_t provenMask, MicroLabelRef defaultLabel)
    {
        MicroBuilder& builder = codeGen.builder();

        // One case left: what no enclosing split has proven yet is what still has to match.
        if (cases.size() == 1)
        {
            emitStringChunksCompare(codeGen, dataReg, cases.front().text, chunks, provenMask, defaultLabel);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, cases.front().bodyLabel);
            return;
        }

        size_t splitIndex = chunks.size();
        size_t splitCount = 1;
        for (size_t index = 0; index < chunks.size(); ++index)
        {
            if (provenMask & (1u << index))
                continue;

            const size_t count = countDistinctChunkValues(cases, chunks[index]);
            if (count > splitCount)
            {
                splitCount = count;
                splitIndex = index;
            }
        }

        // Nothing separates them, which takes two cases testing the same string. Test them where they
        // stand, so the first one still wins.
        if (splitIndex == chunks.size())
        {
            for (const SwitchStringCase& stringCase : cases)
            {
                const MicroLabelRef nextLabel = builder.createLabel();
                emitStringChunksCompare(codeGen, dataReg, stringCase.text, chunks, provenMask, nextLabel);
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, stringCase.bodyLabel);
                builder.placeLabel(nextLabel);
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, defaultLabel);
            return;
        }

        const StringCompareChunk& splitChunk = chunks[splitIndex];

        SmallVector<SwitchStringCase> sorted;
        sorted.reserve(cases.size());
        for (const SwitchStringCase& stringCase : cases)
            sorted.push_back(stringCase);

        const auto chunkKey = [&splitChunk](const SwitchStringCase& stringCase) {
            return stringChunkValue(stringCase.text, splitChunk);
        };
        std::stable_sort(sorted.begin(), sorted.end(), [&chunkKey](const SwitchStringCase& left, const SwitchStringCase& right) { return chunkKey(left) < chunkKey(right); });

        // One target per value the chunk takes; the cases that share a value go on to the next chunk.
        SmallVector<SwitchDispatchEntry> entries;
        SmallVector<size_t>              partitionStarts;
        for (size_t index = 0; index < sorted.size(); ++index)
        {
            const uint64_t value = chunkKey(sorted[index]);
            if (!entries.empty() && entries.back().lowKey == value)
                continue;

            entries.push_back({.lowKey = value, .highKey = value, .label = builder.createLabel()});
            partitionStarts.push_back(index);
        }

        const MicroReg chunkReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(chunkReg, dataReg, splitChunk.offset, splitChunk.opBits);

        const SwitchDispatchSearch search{.codeGen = &codeGen, .valueReg = chunkReg, .opBits = splitChunk.opBits, .useUnsignedCond = true, .defaultLabel = defaultLabel};
        search.emit(entries.span());

        const uint32_t nextMask = provenMask | (1u << splitIndex);
        for (size_t index = 0; index < entries.size(); ++index)
        {
            const size_t first = partitionStarts[index];
            const size_t last  = index + 1 < entries.size() ? partitionStarts[index + 1] : sorted.size();
            builder.placeLabel(entries[index].label);
            emitStringGroupCases(codeGen, dataReg, sorted.span().subspan(first, last - first), chunks, nextMask, defaultLabel);
        }
    }

    // Emits the cases whose strings all have `length` bytes. The switch value is known to have that
    // length by the time control gets here, so nothing tests it again, and the same reads identify
    // every case of the group.
    void emitStringGroupCompare(CodeGen& codeGen, MicroReg valueAddrReg, std::span<const SwitchStringCase> cases, size_t length, MicroLabelRef defaultLabel)
    {
        MicroBuilder& builder = codeGen.builder();

        // The empty string is the only member its group can have.
        if (!length)
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, cases.front().bodyLabel);
            return;
        }

        SmallVector<StringCompareChunk> chunks;
        appendStringCompareChunks(chunks, length);

        const MicroReg dataReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(dataReg, valueAddrReg, offsetof(Runtime::String, ptr), MicroOpBits::B64);
        emitStringGroupCases(codeGen, dataReg, cases, chunks.span(), 0, defaultLabel);
    }

    // Groups the cases by the length of the string they test and dispatches on the length the switch
    // value has. Only the cases of that length can match, and none of them has to test it: a name that
    // matches nothing is rejected by one comparison per distinct length instead of one per case.
    void emitStringSwitchDispatch(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, std::span<const SwitchStringCase> cases, MicroLabelRef defaultLabel)
    {
        MicroBuilder& builder = codeGen.builder();

        SmallVector<size_t> lengths;
        for (const SwitchStringCase& stringCase : cases)
        {
            if (std::ranges::find(lengths, stringCase.text.size()) == lengths.end())
                lengths.push_back(stringCase.text.size());
        }

        std::sort(lengths.begin(), lengths.end());

        SmallVector<SwitchDispatchEntry> entries;
        entries.reserve(lengths.size());
        for (const size_t length : lengths)
            entries.push_back({.lowKey = length, .highKey = length, .label = builder.createLabel()});

        const MicroReg lengthReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(lengthReg, switchState.switchValuePayload.reg, offsetof(Runtime::String, length), MicroOpBits::B64);

        const SwitchDispatchSearch search{.codeGen = &codeGen, .valueReg = lengthReg, .opBits = MicroOpBits::B64, .useUnsignedCond = true, .defaultLabel = defaultLabel};
        search.emit(entries.span());

        SmallVector<SwitchStringCase> group;
        for (size_t index = 0; index < lengths.size(); ++index)
        {
            group.clear();
            for (const SwitchStringCase& stringCase : cases)
            {
                if (stringCase.text.size() == lengths[index])
                    group.push_back(stringCase);
            }

            builder.placeLabel(entries[index].label);
            emitStringGroupCompare(codeGen, switchState.switchValuePayload.reg, group.span(), lengths[index], defaultLabel);
        }
    }

    // The value a case compares against, when it is an integer, character, boolean or enumeration
    // constant the compiler already knows.
    std::optional<uint64_t> knownCaseKey(CodeGen& codeGen, AstNodeRef caseExprRef, MicroOpBits opBits, bool useUnsignedCond)
    {
        if (caseExprRef.isInvalid())
            return std::nullopt;

        const SemaNodeView caseView = codeGen.viewConstant(caseExprRef);
        if (caseView.cstRef().isInvalid())
            return std::nullopt;

        const ConstantValue* constantValue = &codeGen.cstMgr().get(caseView.cstRef());
        if (constantValue->isEnumValue())
            constantValue = &codeGen.cstMgr().get(constantValue->getEnumValue());

        if (constantValue->isBool())
            return switchDispatchKey(constantValue->getBool() ? 1 : 0, opBits, useUnsignedCond);
        if (!constantValue->isInt() && !constantValue->isChar() && !constantValue->isRune())
            return std::nullopt;

        const ApsInt intValue = constantValue->getIntLike();
        if (!intValue.fit64())
            return std::nullopt;

        return switchDispatchKey(intValue.as64(), opBits, useUnsignedCond);
    }

    // The interval of values one case expression selects. False when the compiler cannot know it: an
    // open range bound, or a value only computed at run time. A range with nothing in it comes back
    // with its bounds crossed, and selects nothing.
    bool knownCaseInterval(uint64_t& lowKey, uint64_t& highKey, CodeGen& codeGen, AstNodeRef caseExprRef, MicroOpBits opBits, bool useUnsignedCond)
    {
        lowKey  = 1;
        highKey = 0;

        if (!codeGen.node(caseExprRef).is(AstNodeId::RangeExpr))
        {
            const std::optional<uint64_t> key = knownCaseKey(codeGen, caseExprRef, opBits, useUnsignedCond);
            if (!key.has_value())
                return false;

            lowKey  = *key;
            highKey = *key;
            return true;
        }

        const AstRangeExpr& rangeExpr = codeGen.node(caseExprRef).cast<AstRangeExpr>();
        if (rangeExpr.nodeExprDownRef.isInvalid() || rangeExpr.nodeExprUpRef.isInvalid())
            return false;

        const std::optional<uint64_t> lowValue  = knownCaseKey(codeGen, rangeExpr.nodeExprDownRef, opBits, useUnsignedCond);
        const std::optional<uint64_t> highValue = knownCaseKey(codeGen, rangeExpr.nodeExprUpRef, opBits, useUnsignedCond);
        if (!lowValue.has_value() || !highValue.has_value())
            return false;

        if (rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive))
        {
            if (switchDispatchKeyLess(*highValue, *lowValue, useUnsignedCond))
                return true;

            lowKey  = *lowValue;
            highKey = *highValue;
            return true;
        }

        // An exclusive range stops before its upper bound, so one that starts there holds nothing.
        if (!switchDispatchKeyLess(*lowValue, *highValue, useUnsignedCond))
            return true;

        lowKey  = *lowValue;
        highKey = *highValue - 1;
        return true;
    }

    // Reduces every case to the intervals of values that select its body. The dispatch is only sound
    // when they do not overlap: a value two cases claim belongs to the first one, and a search over
    // sorted intervals has no way to know which that was.
    bool collectIntSwitchIntervals(SmallVector<SwitchDispatchEntry>& entries, CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, std::span<const AstNodeRef> caseRefs)
    {
        for (const AstNodeRef caseRef : caseRefs)
        {
            const auto&         caseNode     = codeGen.node(caseRef).cast<AstSwitchCaseStmt>();
            const MicroLabelRef bodyLabel    = switchCaseBodyLabel(switchState, caseRef);
            const auto          caseExprRefs = collectSwitchCaseExprRefs(codeGen, caseNode);
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                uint64_t lowKey  = 0;
                uint64_t highKey = 0;
                if (!knownCaseInterval(lowKey, highKey, codeGen, caseExprRef, switchState.compareOpBits, switchState.useUnsignedCond))
                    return false;
                if (switchDispatchKeyLess(highKey, lowKey, switchState.useUnsignedCond))
                    continue;

                entries.push_back({.lowKey = lowKey, .highKey = highKey, .label = bodyLabel});
            }
        }

        if (entries.empty())
            return false;

        const bool useUnsignedCond = switchState.useUnsignedCond;
        std::sort(entries.begin(), entries.end(), [useUnsignedCond](const SwitchDispatchEntry& left, const SwitchDispatchEntry& right) { return switchDispatchKeyLess(left.lowKey, right.lowKey, useUnsignedCond); });

        SmallVector<SwitchDispatchEntry> merged;
        merged.reserve(entries.size());
        for (const SwitchDispatchEntry& entry : entries)
        {
            if (!merged.empty())
            {
                SwitchDispatchEntry& previous = merged.back();
                if (!switchDispatchKeyLess(previous.highKey, entry.lowKey, useUnsignedCond))
                    return false;

                // Neighbouring intervals that select the same body are one interval.
                if (previous.label == entry.label && previous.highKey + 1 == entry.lowKey)
                {
                    previous.highKey = entry.highKey;
                    continue;
                }
            }

            merged.push_back(entry);
        }

        entries = std::move(merged);
        return true;
    }

    bool collectTypeSwitchEntries(SmallVector<SwitchDispatchEntry>& entries, MicroLabelRef& nullLabel, CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, std::span<const AstNodeRef> caseRefs)
    {
        for (const AstNodeRef caseRef : caseRefs)
        {
            const auto&         caseNode     = codeGen.node(caseRef).cast<AstSwitchCaseStmt>();
            const MicroLabelRef bodyLabel    = switchCaseBodyLabel(switchState, caseRef);
            const auto          caseExprRefs = collectSwitchCaseExprRefs(codeGen, caseNode);
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                const SemaNodeView caseView = codeGen.viewConstant(caseExprRef);
                if (caseView.cstRef().isInvalid())
                    return false;

                const ConstantValue& constantValue = codeGen.cstMgr().get(caseView.cstRef());
                if (constantValue.isNull() || (constantValue.isValuePointer() && !constantValue.getValuePointer()))
                {
                    if (nullLabel.isValid())
                        return false;
                    nullLabel = bodyLabel;
                    continue;
                }

                if (!constantValue.isValuePointer())
                    return false;

                const auto* descriptor = reinterpret_cast<const Runtime::TypeInfo*>(constantValue.getValuePointer());
                entries.push_back({.lowKey = descriptor->crc, .highKey = descriptor->crc, .label = bodyLabel});
            }
        }

        std::sort(entries.begin(), entries.end(), [](const SwitchDispatchEntry& left, const SwitchDispatchEntry& right) { return left.lowKey < right.lowKey; });
        for (size_t index = 1; index < entries.size(); ++index)
        {
            if (entries[index - 1].lowKey == entries[index].lowKey)
                return false;
        }

        return !entries.empty() || nullLabel.isValid();
    }

    bool emitTypeSwitchDispatch(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, std::span<const AstNodeRef> caseRefs, MicroLabelRef defaultLabel)
    {
        SmallVector<SwitchDispatchEntry> entries;
        MicroLabelRef                    nullLabel = MicroLabelRef::invalid();
        if (!collectTypeSwitchEntries(entries, nullLabel, codeGen, switchState, caseRefs))
            return false;

        MicroBuilder& builder = codeGen.builder();
        builder.emitCmpRegImm(switchState.switchValueReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nullLabel.isValid() ? nullLabel : defaultLabel);
        if (entries.empty())
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, defaultLabel);
            return true;
        }

        const MicroReg hashReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(hashReg, switchState.switchValueReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);
        const SwitchDispatchSearch search{.codeGen = &codeGen, .valueReg = hashReg, .opBits = MicroOpBits::B32, .useUnsignedCond = true, .defaultLabel = defaultLabel};
        search.emit(entries.span());
        return true;
    }

    // Replaces testing every case in turn with one search over the values the cases name, emitted
    // right after the switch value is computed and jumping straight to the body that matches.
    //
    // Source order stops mattering once the cases are searched instead of scanned, so this only takes
    // over a switch where that cannot change what matches: every case value known at compile time, no
    // `where` clause to run after a match, no value claimed by two cases, and a `default` last if
    // there is one.
    bool emitSwitchDispatch(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const AstSwitchStmt& switchNode)
    {
        if (!switchState.hasExpression || switchState.dynamicStructSwitch)
            return false;

        const TypeInfo& compareType = codeGen.typeMgr().get(switchState.compareTypeRef);
        const bool      intSwitch   = compareType.isNumericIntLike() && getBitsMask(switchState.compareOpBits) != 0;
        if (!intSwitch && !switchState.useStringCompare && !switchState.useTypeInfoCompare)
            return false;
        if (switchState.useStringCompare && !switchState.switchValuePayload.isAddress())
            return false;

        SmallVector<AstNodeRef> caseRefs = collectSwitchCaseRefs(codeGen, switchNode);
        if (caseRefs.empty())
            return false;

        for (const AstNodeRef caseRef : caseRefs)
        {
            if (codeGen.node(caseRef).cast<AstSwitchCaseStmt>().nodeWhereRef.isValid())
                return false;
        }

        // A `default` is where the search sends everything it did not match. Anywhere but last it
        // would also make the cases behind it unreachable, which the search cannot reproduce.
        for (size_t index = 0; index + 1 < caseRefs.size(); ++index)
        {
            if (!codeGen.node(caseRefs[index]).cast<AstSwitchCaseStmt>().spanExprRef.isValid())
                return false;
        }

        MicroLabelRef defaultLabel = switchState.noMatchLabel.isValid() ? switchState.noMatchLabel : switchState.doneLabel;
        if (!codeGen.node(caseRefs.back()).cast<AstSwitchCaseStmt>().spanExprRef.isValid())
        {
            defaultLabel = switchCaseBodyLabel(switchState, caseRefs.back());
            caseRefs.pop_back();
        }

        if (caseRefs.empty())
            return false;

        if (switchState.useTypeInfoCompare)
            return emitTypeSwitchDispatch(codeGen, switchState, caseRefs.span(), defaultLabel);

        if (intSwitch)
        {
            SmallVector<SwitchDispatchEntry> entries;
            if (!collectIntSwitchIntervals(entries, codeGen, switchState, caseRefs.span()))
                return false;

            const SwitchDispatchSearch search{.codeGen         = &codeGen,
                                               .valueReg        = switchState.switchValueReg,
                                               .opBits          = switchState.compareOpBits,
                                               .useUnsignedCond = switchState.useUnsignedCond,
                                               .allowJumpTable  = true,
                                               .defaultLabel    = defaultLabel};
            search.emit(entries.span());
            return true;
        }

        SmallVector<SwitchStringCase> cases;
        if (!collectStringSwitchCases(cases, codeGen, switchState, caseRefs.span()))
            return false;

        emitStringSwitchDispatch(codeGen, switchState, cases.span(), defaultLabel);
        return true;
    }

    void emitSwitchCaseWhereFalseJump(CodeGen& codeGen, AstNodeRef whereRef, MicroLabelRef failLabel)
    {
        if (!whereRef.isValid())
            return;

        const CodeGenNodePayload& wherePayload = codeGen.payload(whereRef);
        const SemaNodeView        whereView    = codeGen.viewType(whereRef);
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
    }

    Result emitSwitchCaseWhereBodyGate(CodeGen& codeGen, AstNodeRef whereRef, MicroLabelRef matchLabel, MicroLabelRef failLabel, MicroLabelRef bodyLabel)
    {
        if (!whereRef.isValid())
            return Result::Continue;

        MicroBuilder& builder = codeGen.builder();
        builder.placeLabel(matchLabel);
        emitSwitchCaseWhereFalseJump(codeGen, whereRef, failLabel);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, bodyLabel);
        return Result::Continue;
    }

    Result initializeDynamicStructSwitchState(CodeGen& codeGen, SwitchStmtCodeGenPayload& switchState, TypeRef compareTypeRef, const TypeInfo& compareType, const CodeGenNodePayload& exprPayload)
    {
        switchState.compareTypeRef      = compareTypeRef;
        switchState.switchValuePayload  = exprPayload;
        switchState.dynamicStructSwitch = true;
        switchState.isAnySwitch         = compareType.isAny();
        switchState.dynamicAsFunction   = runtimeDynamicAsFunction(codeGen);
        switchState.dynamicIsFunction   = runtimeDynamicIsFunction(codeGen);

        SWC_ASSERT(exprPayload.isAddress());
        if (!exprPayload.isAddress())
            return Result::Error;

        MicroBuilder& builder            = codeGen.builder();
        switchState.dynamicSourceTypeReg = codeGen.nextVirtualIntRegister();
        switchState.dynamicSourcePtrReg  = codeGen.nextVirtualIntRegister();

        if (compareType.isAny())
        {
            // Any: typeinfo is stored directly, data pointer is 'value'
            const MicroReg typeReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(typeReg, exprPayload.reg, offsetof(Runtime::Any, type), MicroOpBits::B64);

            builder.emitLoadRegImm(switchState.dynamicSourceTypeReg, ApInt(0, 64), MicroOpBits::B64);
            const MicroLabelRef typeDoneLabel = builder.createLabel();
            builder.emitCmpRegImm(typeReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, typeDoneLabel);
            builder.emitLoadRegReg(switchState.dynamicSourceTypeReg, typeReg, MicroOpBits::B64);
            builder.placeLabel(typeDoneLabel);

            builder.emitLoadRegMem(switchState.dynamicSourcePtrReg, exprPayload.reg, offsetof(Runtime::Any, value), MicroOpBits::B64);
            return Result::Continue;
        }

        // Interface: typeinfo is first entry in itable
        const MicroReg itableReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(itableReg, exprPayload.reg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);

        builder.emitLoadRegImm(switchState.dynamicSourceTypeReg, ApInt(0, 64), MicroOpBits::B64);
        const MicroLabelRef typeDoneLabel = builder.createLabel();
        builder.emitCmpRegImm(itableReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, typeDoneLabel);
        builder.emitLoadRegMem(switchState.dynamicSourceTypeReg, itableReg, 0, MicroOpBits::B64);
        builder.placeLabel(typeDoneLabel);

        builder.emitLoadRegMem(switchState.dynamicSourcePtrReg, exprPayload.reg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
        return Result::Continue;
    }

}

Result AstSwitchStmt::codeGenPreNode(CodeGen& codeGen) const
{
    MicroBuilder&            builder = codeGen.builder();
    SwitchStmtCodeGenPayload switchState;
    switchState.doneLabel     = builder.createLabel();
    switchState.hasExpression = nodeExprRef.isValid();
    const auto* semaPayload   = codeGen.sema().semaPayload<SwitchPayload>(codeGen.curNodeRef());
    if (semaPayload && semaPayload->hasRuntimeSwitchSafety)
        switchState.noMatchLabel = builder.createLabel();

    // Build the whole case label graph up front so `fallthrough` and "next test" edges are stable before
    // any case body starts emitting code.
    const auto caseRefs = collectSwitchCaseRefs(codeGen, *this);
    for (const AstNodeRef caseRef : caseRefs)
    {
        SwitchCaseCodeGenPayload caseState;
        caseState.testLabel = builder.createLabel();
        caseState.bodyLabel = builder.createLabel();
        switchState.caseStates.insert_or_assign(caseRef, caseState);
    }

    for (size_t i = 0; i < caseRefs.size(); ++i)
    {
        const AstNodeRef caseRef = caseRefs[i];
        const auto       itCase  = switchState.caseStates.find(caseRef);
        SWC_ASSERT(itCase != switchState.caseStates.end());

        SwitchCaseCodeGenPayload& caseState = itCase->second;
        if (i + 1 < caseRefs.size())
        {
            const AstNodeRef nextCaseRef = caseRefs[i + 1];
            const auto       itNextCase  = switchState.caseStates.find(nextCaseRef);
            SWC_ASSERT(itNextCase != switchState.caseStates.end());

            caseState.hasNextCase   = true;
            caseState.nextCaseRef   = nextCaseRef;
            caseState.nextTestLabel = itNextCase->second.testLabel;
            caseState.nextBodyLabel = itNextCase->second.bodyLabel;
        }
    }

    setSwitchStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), switchState);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Switch);
    frame.setCurrentSwitch(codeGen.curNodeRef());
    frame.setCurrentSwitchCase(AstNodeRef::invalid());
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstSwitchStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef)
{
    if (!codeGen.node(childRef).is(AstNodeId::SwitchCaseStmt))
        return Result::Continue;

    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(switchState != nullptr);

    const auto itCase = switchState->caseStates.find(childRef);
    SWC_ASSERT(itCase != switchState->caseStates.end());

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(itCase->second.testLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentSwitchCase(childRef);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstSwitchStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(switchState != nullptr);

    const AstNodeRef exprRef = codeGen.resolvedNodeRef(nodeExprRef);
    if (childRef == exprRef)
    {
        const SemaNodeView        exprView       = codeGen.viewType(exprRef);
        const CodeGenNodePayload& exprPayload    = codeGen.payload(exprRef);
        const TypeInfo&           exprType       = codeGen.typeMgr().get(exprView.typeRef());
        const TypeRef             compareTypeRef = exprType.unwrapAliasEnum(codeGen.ctx(), exprView.typeRef());
        const TypeInfo&           compareType    = codeGen.typeMgr().get(compareTypeRef);
        if (isDynamicStructSwitchType(codeGen, compareTypeRef))
            return initializeDynamicStructSwitchState(codeGen, *switchState, compareTypeRef, compareType, exprPayload);

        const MicroOpBits compareBits      = switchCompareOpBits(compareType, codeGen.ctx());
        const bool        useStringCompare = CodeGenTypeHelpers::isStringCompareType(codeGen.ctx(), compareTypeRef);
        MicroBuilder&     builder          = codeGen.builder();

        const MicroReg switchValueReg = codeGen.nextVirtualRegisterForType(compareTypeRef);
        if (exprPayload.isAddress())
            builder.emitLoadRegMem(switchValueReg, exprPayload.reg, 0, compareBits);
        else
            builder.emitLoadRegReg(switchValueReg, exprPayload.reg, compareBits);

        switchState->compareTypeRef     = compareTypeRef;
        switchState->switchValuePayload = exprPayload;
        switchState->switchValueReg     = switchValueReg;
        switchState->compareOpBits      = compareBits;
        switchState->useStringCompare   = useStringCompare;
        switchState->useTypeInfoCompare = compareType.isAnyTypeInfo(codeGen.ctx());
        switchState->useUnsignedCond    = compareType.usesUnsignedConditions();
        if (useStringCompare)
            switchState->stringCmpFunction = runtimeStringCompareFunction(codeGen);

        switchState->dispatchOwnsTests = emitSwitchDispatch(codeGen, *switchState, *this);
        return Result::Continue;
    }

    if (codeGen.node(childRef).is(AstNodeId::SwitchCaseStmt))
        codeGen.popFrame();

    return Result::Continue;
}

Result AstSwitchStmt::codeGenPostNode(CodeGen& codeGen)
{
    const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(switchState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    if (switchState->noMatchLabel.isValid())
    {
        builder.placeLabel(switchState->noMatchLabel);
        const auto&          switchNode    = codeGen.node(codeGen.curNodeRef()).cast<AstSwitchStmt>();
        const AstNodeRef     switchExprRef = codeGen.resolvedNodeRef(switchNode.nodeExprRef);
        const SwitchPayload* semaPayload   = codeGen.sema().semaPayload<SwitchPayload>(codeGen.curNodeRef());
        const Result         result        = CodeGenSafety::emitSwitchCheck(codeGen, codeGen.node(switchExprRef), semaPayload ? semaPayload->runtimePanicSymbol : nullptr);
        if (result != Result::Continue)
            return result;
    }

    builder.placeLabel(switchState->doneLabel);
    codeGen.popFrame();
    eraseSwitchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstSwitchCaseStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    if (switchRef.isInvalid())
        return Result::Continue;

    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);

    const auto itCase = switchState->caseStates.find(codeGen.curNodeRef());
    SWC_ASSERT(itCase != switchState->caseStates.end());

    const SwitchCaseCodeGenPayload& caseState = itCase->second;
    const MicroLabelRef             failLabel = caseState.hasNextCase
                                                    ? caseState.nextTestLabel
                                                    : (switchState->noMatchLabel.isValid() ? switchState->noMatchLabel : switchState->doneLabel);

    MicroBuilder& builder = codeGen.builder();

    // The dispatch emitted before the first case already compared every case value and jumped to the
    // body that matched, so nothing is left to test here, and the case expressions - constants, all
    // of them - are not even evaluated.
    if (switchState->dispatchOwnsTests)
    {
        if (childRef != nodeBodyRef)
            return Result::SkipChildren;

        builder.placeLabel(caseState.bodyLabel);
        codeGen.pushDeferScope(AstNodeRef::invalid(), switchRef, codeGen.curNodeRef());
        return Result::Continue;
    }

    if (switchState->dynamicStructSwitch && spanExprRef.isValid())
    {
        if (childRef == nodeWhereRef)
        {
            const MicroLabelRef matchLabel = builder.createLabel();
            SWC_RESULT(emitDynamicStructSwitchCaseTests(codeGen, *switchState, codeGen.curNodeRef(), matchLabel, failLabel));
            builder.placeLabel(matchLabel);
            return Result::Continue;
        }

        if (childRef == nodeBodyRef)
        {
            if (!nodeWhereRef.isValid())
            {
                SWC_RESULT(emitDynamicStructSwitchCaseTests(codeGen, *switchState, codeGen.curNodeRef(), caseState.bodyLabel, failLabel));
            }
            else
            {
                emitSwitchCaseWhereFalseJump(codeGen, nodeWhereRef, failLabel);
            }

            builder.placeLabel(caseState.bodyLabel);
            codeGen.pushDeferScope(AstNodeRef::invalid(), switchRef, codeGen.curNodeRef());
        }

        return Result::Continue;
    }

    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (switchState->hasExpression)
    {
        if (spanExprRef.isValid())
        {
            const auto caseExprRefs = collectSwitchCaseExprRefs(codeGen, *this);
            const bool hasWhere     = nodeWhereRef.isValid();
            // A `where` clause only runs after one case expression matched, so all successful tests funnel
            // through a shared label before entering the body.
            const MicroLabelRef matchLabel = hasWhere ? builder.createLabel() : caseState.bodyLabel;
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                if (codeGen.node(caseExprRef).is(AstNodeId::RangeExpr))
                {
                    const AstRangeExpr& rangeExpr = codeGen.node(caseExprRef).cast<AstRangeExpr>();
                    emitSwitchRangeFailJumps(codeGen, *switchState, rangeExpr, failLabel);
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, matchLabel);
                }
                else
                {
                    SWC_RESULT(emitSwitchValueEqualsJump(codeGen, *switchState, caseExprRef, matchLabel));
                }
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, failLabel);
            SWC_RESULT(emitSwitchCaseWhereBodyGate(codeGen, nodeWhereRef, matchLabel, failLabel, caseState.bodyLabel));
        }
        else
        {
            emitSwitchCaseWhereFalseJump(codeGen, nodeWhereRef, failLabel);

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
        }
    }
    else
    {
        if (spanExprRef.isValid())
        {
            const auto          caseExprRefs = collectSwitchCaseExprRefs(codeGen, *this);
            const bool          hasWhere     = nodeWhereRef.isValid();
            const MicroLabelRef matchLabel   = hasWhere ? builder.createLabel() : caseState.bodyLabel;
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                const CodeGenNodePayload& exprPayload = codeGen.payload(caseExprRef);
                const SemaNodeView        exprView    = codeGen.viewType(caseExprRef);
                emitConditionTrueJump(codeGen, exprPayload, exprView.typeRef(), matchLabel);
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, failLabel);
            SWC_RESULT(emitSwitchCaseWhereBodyGate(codeGen, nodeWhereRef, matchLabel, failLabel, caseState.bodyLabel));
        }
        else
        {
            emitSwitchCaseWhereFalseJump(codeGen, nodeWhereRef, failLabel);

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
        }
    }

    builder.placeLabel(caseState.bodyLabel);
    codeGen.pushDeferScope(AstNodeRef::invalid(), switchRef, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstSwitchCaseStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    SWC_RESULT(codeGen.popDeferScope());
    if (caseBodyEndsWithFallthrough(codeGen, *this))
        return Result::Continue;

    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    if (switchRef.isInvalid())
        return Result::Continue;

    const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);

    // Only non-fallthrough cases jump to the switch exit; explicit `fallthrough` leaves control to the
    // next case's test/body sequence.
    MicroBuilder& builder = codeGen.builder();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, switchState->doneLabel);
    return Result::Continue;
}

Result AstBreakStmt::codeGenPostNode(CodeGen& codeGen)
{
    const CodeGenFrame::BreakContext breakCtx = codeGen.frame().currentBreakContext();
    if (breakCtx.kind == CodeGenFrame::BreakContextKind::None)
        return Result::Continue;

    const MicroLabelRef breakLabel = codeGen.frame().currentLoopBreakLabel();
    const AstNodeRef    switchRef  = codeGen.frame().currentSwitch();

    SWC_RESULT(codeGen.emitDeferredActionsUntilBreakOwner(breakCtx.nodeRef));

    if (breakCtx.kind == CodeGenFrame::BreakContextKind::Loop)
    {
        if (breakLabel != MicroLabelRef::invalid())
        {
            MicroBuilder& builder = codeGen.builder();
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, breakLabel);
        }
        return Result::Continue;
    }

    SWC_ASSERT(switchRef.isValid());

    const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);
    MicroBuilder& builder = codeGen.builder();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, switchState->doneLabel);
    return Result::Continue;
}

Result AstUnreachableStmt::codeGenPostNode(CodeGen& codeGen)
{
    return CodeGenSafety::emitUnreachableCheck(codeGen, codeGen.curNode());
}

Result AstFallThroughStmt::codeGenPostNode(CodeGen& codeGen)
{
    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    const AstNodeRef caseRef   = codeGen.frame().currentSwitchCase();
    if (switchRef.isInvalid() || caseRef.isInvalid())
        return Result::Continue;

    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);

    const auto itCase = switchState->caseStates.find(caseRef);
    SWC_ASSERT(itCase != switchState->caseStates.end());
    if (!itCase->second.hasNextCase)
        return Result::Continue;

    SWC_RESULT(codeGen.emitDeferredActionsUntilSwitchCase(caseRef));
    MicroBuilder&       builder = codeGen.builder();
    const MicroLabelRef targetLabel =
        isDynamicStructSwitchCaseTarget(codeGen, switchRef, itCase->second.nextCaseRef) ? itCase->second.nextTestLabel : itCase->second.nextBodyLabel;
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, targetLabel);
    return Result::Continue;
}

SWC_END_NAMESPACE();

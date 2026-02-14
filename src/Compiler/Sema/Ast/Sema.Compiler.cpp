#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/Logger.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerExpression::semaPostNode(Sema& sema)
{
    RESULT_VERIFY(SemaCheck::isConstant(sema, nodeExprRef));
    sema.inheritSema(*this, nodeExprRef);
    return Result::Continue;
}

Result AstCompilerIf::semaPreDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return Result::Continue;

    if (childRef == nodeIfBlockRef)
    {
        SemaFrame       frame    = sema.frame();
        SemaCompilerIf* parentIf = frame.currentCompilerIf();
        SemaCompilerIf* ifFrame  = sema.compiler().allocate<SemaCompilerIf>();
        ifFrame->parent          = parentIf;

        frame.setCurrentCompilerIf(ifFrame);
        sema.setPayload(nodeIfBlockRef, ifFrame);
        sema.pushFramePopOnPostChild(frame, childRef);
        return Result::Continue;
    }

    SWC_ASSERT(childRef == nodeElseBlockRef);
    if (nodeElseBlockRef.isValid())
    {
        SemaFrame       frame     = sema.frame();
        SemaCompilerIf* parentIf  = frame.currentCompilerIf();
        SemaCompilerIf* elseFrame = sema.compiler().allocate<SemaCompilerIf>();
        elseFrame->parent         = parentIf;

        frame.setCurrentCompilerIf(elseFrame);
        sema.setPayload(nodeElseBlockRef, elseFrame);
        sema.pushFramePopOnPostChild(frame, childRef);
    }

    return Result::Continue;
}

Result AstCompilerIf::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return Result::Continue;

    const SemaNodeView condView(sema, nodeConditionRef);
    SWC_ASSERT(condView.cst);
    if (!condView.cst->isBool())
        return SemaError::raiseInvalidType(sema, nodeConditionRef, condView.cst->typeRef(), sema.typeMgr().typeBool());

    if (childRef == nodeIfBlockRef && !condView.cst->getBool())
        return Result::SkipChildren;
    if (childRef == nodeElseBlockRef && condView.cst->getBool())
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstCompilerIf::semaPostNode(Sema& sema) const
{
    // Condition must already be a constant at this point
    SWC_ASSERT(sema.hasConstant(nodeConditionRef));

    const SemaNodeView condView(sema, nodeConditionRef);
    SWC_ASSERT(condView.cst);
    const bool takenIfBranch = condView.cst->getBool();

    // The block that will be ignored
    const AstNodeRef& ignoredBlockRef = takenIfBranch ? nodeElseBlockRef : nodeIfBlockRef;
    if (!ignoredBlockRef.isValid())
        return Result::Continue;

    // Retrieve the SemaCompilerIf payload
    if (sema.hasPayload(ignoredBlockRef))
    {
        const SemaCompilerIf* ignoredIfData = sema.payload<SemaCompilerIf>(ignoredBlockRef);
        if (!ignoredIfData)
            return Result::Continue;

        for (Symbol* sym : ignoredIfData->symbols)
            sym->setIgnored(sema.ctx());
    }

    return Result::Continue;
}

Result AstCompilerDiagnostic::semaPostNode(Sema& sema) const
{
    SWC_ASSERT(sema.hasConstant(nodeArgRef));

    const Token&       tok = sema.token(codeRef());
    const SemaNodeView argView(sema, nodeArgRef);
    SWC_ASSERT(argView.cst);
    const ConstantValue& constant = *argView.cst;
    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
                return SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeString());
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
                return SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeBool());
            if (!constant.getBool())
                return SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, codeRef());
            break;

        default:
            break;
    }

    switch (tok.id)
    {
        case TokenId::CompilerError:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, codeRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString());
            diag.report(sema.ctx());
            return Result::Error;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_warn_compiler_warning, codeRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString());
            diag.report(sema.ctx());
            return Result::Continue;
        }

        case TokenId::CompilerPrint:
        {
            const auto& ctx = sema.ctx();
            ctx.global().logger().lock();
            Logger::print(ctx, constant.toString(ctx));
            Logger::print(ctx, "\n");
            ctx.global().logger().unlock();
            return Result::Continue;
        }

        case TokenId::CompilerAssert:
            if (!constant.getBool())
                return SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, codeRef());
            break;

        default:
            break;
    }

    return Result::Continue;
}

Result AstCompilerLiteral::semaPostNode(Sema& sema)
{
    auto&             ctx     = sema.ctx();
    const Token&      tok     = sema.token(codeRef());
    const SourceView& srcView = sema.ast().srcView();

    switch (tok.id)
    {
        case TokenId::CompilerFile:
        {
            const SourceFile*    file = sema.ast().srcView().file();
            const ConstantValue& val  = ConstantValue::makeString(ctx, file ? file->path().string() : "");
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerLine:
        {
            const SourceCodeRange codeRange = tok.codeRange(ctx, srcView);
            const ConstantValue&  val       = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(codeRange.line), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcVersion:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_VERSION), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcRevision:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_REVISION), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcBuildNum:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_BUILD_NUM), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerOs:
        {
            TypeRef typeRef = TypeRef::invalid();
            RESULT_VERIFY(sema.waitPredefined(IdentifierManager::PredefinedName::TargetOs, typeRef, codeRef()));
            const ConstantRef   valueCst     = sema.cstMgr().addS32(ctx, static_cast<int32_t>(sema.ctx().cmdLine().targetOs));
            const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCst, typeRef);
            const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
            sema.setConstant(sema.curNodeRef(), enumValueRef);
            break;
        }

        case TokenId::CompilerCallerFunction:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeString());
            sema.setIsValue(*this);
            break;
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerCurLocation:
        {
            TypeRef typeRef = TypeRef::invalid();
            RESULT_VERIFY(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, codeRef()));
            sema.setConstant(sema.curNodeRef(), ConstantHelpers::makeSourceCodeLocation(sema, *this));
            break;
        }

        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerBuildCfg:
        case TokenId::CompilerModule:
        case TokenId::CompilerSwagOs:
        case TokenId::CompilerBackend:
        case TokenId::CompilerScopeName:
            // TODO
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }

    return Result::Continue;
}

Result AstCompilerGlobal::semaPreDecl(Sema& sema) const
{
    switch (mode)
    {
        case Mode::AccessPublic:
            sema.frame().setCurrentAccess(SymbolAccess::Public);
            break;
        case Mode::AccessInternal:
            sema.frame().setCurrentAccess(SymbolAccess::Internal);
            break;
        case Mode::AccessPrivate:
            sema.frame().setCurrentAccess(SymbolAccess::Private);
            break;
        case Mode::Namespace:
            return AstNamespaceDecl::pushNamespace(sema, this, spanNameRef);
        default:
            break;
    }

    return Result::Continue;
}

Result AstCompilerGlobal::semaPreNode(Sema& sema) const
{
    return semaPreDecl(sema);
}

namespace
{
    Result semaCompilerGlobalIf(Sema& sema, const AstCompilerGlobal& node)
    {
        RESULT_VERIFY(SemaCheck::isConstant(sema, node.nodeModeRef));
        const SemaNodeView condView(sema, node.nodeModeRef);

        SWC_ASSERT(condView.cst);
        if (!condView.cst->isBool())
            return SemaError::raiseInvalidType(sema, node.nodeModeRef, condView.cst->typeRef(), sema.typeMgr().typeBool());

        sema.frame().setGlobalCompilerIfEnabled(condView.cst->getBool());
        return Result::SkipChildren;
    }
}

Result AstCompilerGlobal::semaPostNode(Sema& sema) const
{
    switch (mode)
    {
        case Mode::Skip:
        case Mode::Generated:
            return Result::Continue;

        case Mode::CompilerIf:
            return semaCompilerGlobalIf(sema, *this);

        case Mode::Export:
        case Mode::AttributeList:
        case Mode::Using:
        case Mode::SkipFmt:
            // TODO
            return Result::SkipChildren;

        default:
            break;
    }

    return Result::Continue;
}

namespace
{
    Result semaCompilerTypeOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     nodeView(sema, childRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.cstRef.isValid())
        {
            ConstantRef newCstRef;
            RESULT_VERIFY(Cast::concretizeConstant(sema, newCstRef, nodeView.nodeRef, nodeView.cstRef, TypeInfo::Sign::Unknown));
            nodeView.setCstRef(sema, newCstRef);
        }

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), nodeView.typeRef));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    Result semaCompilerKindOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     nodeView(sema, childRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.type->isEnum())
        {
            const TypeRef     typeRef = nodeView.type->payloadSymEnum().underlyingTypeRef();
            const ConstantRef cstRef  = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeRef));
            nodeView.setCstRef(sema, cstRef);
            sema.setConstant(sema.curNodeRef(), cstRef);
            return Result::Continue;
        }

        return semaCompilerTypeOf(sema, node);
    }

    Result semaCompilerSizeOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);
        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, childRef);
        RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, childRef));

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), nodeView.type->sizeOf(sema.ctx())));
        return Result::Continue;
    }

    Result semaCompilerOffsetOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);
        if (!nodeView.sym || !nodeView.sym->isVariable())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, childRef);

        const SymbolVariable& symVar = nodeView.sym->cast<SymbolVariable>();
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), symVar.offset()));
        return Result::Continue;
    }

    Result semaCompilerAlignOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);
        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, childRef);
        RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, childRef));

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), nodeView.type->alignOf(sema.ctx())));
        return Result::Continue;
    }

    Result semaCompilerNameOf(Sema& sema, const AstCompilerCallOne& node)
    {
        auto&            ctx      = sema.ctx();
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     nodeView(sema, childRef);

        if (nodeView.sym)
        {
            const std::string_view name  = nodeView.sym->name(ctx);
            const ConstantValue    value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeView));
        if (nodeView.type && nodeView.type->isTypeValue())
        {
            const Utf8          name  = sema.typeMgr().get(nodeView.type->payloadTypeRef()).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return SemaError::raise(sema, DiagnosticId::sema_err_failed_nameof, childRef);
    }

    Result semaCompilerFullNameOf(Sema& sema, const AstCompilerCallOne& node)
    {
        auto&              ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);

        if (nodeView.sym)
        {
            const Utf8          name  = nodeView.sym->getFullScopedName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return semaCompilerNameOf(sema, node);
    }

    Result semaCompilerStringOf(Sema& sema, const AstCompilerCallOne& node)
    {
        auto&              ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);

        if (nodeView.cst)
        {
            const Utf8          name  = nodeView.cst->toString(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return semaCompilerNameOf(sema, node);
    }

    Result semaCompilerDefined(Sema& sema, const AstCompilerCallOne& node)
    {
        auto&              ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);

        const bool          isDefined = nodeView.sym != nullptr;
        const ConstantValue value     = ConstantValue::makeBool(ctx, isDefined);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }

    Result semaCompilerLocation(Sema& sema, const AstCompilerCallOne& node)
    {
        TypeRef typeRef = TypeRef::invalid();
        RESULT_VERIFY(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, node.codeRef()));

        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView nodeView(sema, childRef);
        if (!nodeView.sym)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_location, childRef);

        const SourceCodeRange codeRange = nodeView.sym->codeRange(sema.ctx());
        sema.setConstant(sema.curNodeRef(), ConstantHelpers::makeSourceCodeLocation(sema, codeRange));
        return Result::Continue;
    }

    Result semaCompilerForeignLib(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        RESULT_VERIFY(SemaCheck::isConstant(sema, childRef));

        const SemaNodeView nodeView(sema, childRef);
        SWC_ASSERT(nodeView.cst);
        if (!nodeView.cst->isString())
            return SemaError::raiseInvalidType(sema, childRef, nodeView.cst->typeRef(), sema.typeMgr().typeString());

        sema.compiler().registerForeignLib(nodeView.cst->getString());
        return Result::Continue;
    }
}

Result AstCompilerCallOne::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::CompilerTypeOf:
            return semaCompilerTypeOf(sema, *this);
        case TokenId::CompilerKindOf:
            return semaCompilerKindOf(sema, *this);
        case TokenId::CompilerNameOf:
            return semaCompilerNameOf(sema, *this);
        case TokenId::CompilerFullNameOf:
            return semaCompilerFullNameOf(sema, *this);
        case TokenId::CompilerStringOf:
            return semaCompilerStringOf(sema, *this);
        case TokenId::CompilerSizeOf:
            return semaCompilerSizeOf(sema, *this);
        case TokenId::CompilerOffsetOf:
            return semaCompilerOffsetOf(sema, *this);
        case TokenId::CompilerAlignOf:
            return semaCompilerAlignOf(sema, *this);
        case TokenId::CompilerDefined:
            return semaCompilerDefined(sema, *this);
        case TokenId::CompilerLocation:
            return semaCompilerLocation(sema, *this);
        case TokenId::CompilerForeignLib:
            return semaCompilerForeignLib(sema, *this);

        case TokenId::CompilerHasTag:
        case TokenId::CompilerDeclType:
        case TokenId::CompilerRunes:
        case TokenId::CompilerIsConstExpr:
        case TokenId::CompilerSafety:
        case TokenId::CompilerInject:
        case TokenId::CompilerInclude:
        case TokenId::CompilerLoad:
            // TODO
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstCompilerCall::semaPostNode(const Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::CompilerGetTag:
            // TODO
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstCompilerFunc::semaPreDecl(Sema& sema)
{
    auto&        ctx = sema.ctx();
    const Token& tok = sema.token(codeRef());
    if (tok.id == TokenId::CompilerFuncMain)
    {
        if (!ctx.compiler().setMainFunc(this))
        {
            auto  diag = SemaError::report(sema, DiagnosticId::sema_err_already_defined, codeRef());
            auto& note = diag.addElement(DiagnosticId::sema_note_other_definition);
            note.setSeverity(DiagnosticSeverity::Note);
            const AstCompilerFunc* mainFunc = ctx.compiler().mainFunc();
            const SourceView&      srcView  = mainFunc->srcView(ctx);
            note.addSpan(srcView.tokenCodeRange(ctx, mainFunc->tokRef()));
            diag.report(ctx);
            return Result::Error;
        }
    }

    std::string_view name;
    switch (tok.id)
    {
        case TokenId::CompilerRun:
        case TokenId::CompilerAst:
            name = "run";
            break;
        case TokenId::CompilerFuncTest:
            name = "test";
            break;
        case TokenId::CompilerFuncInit:
            name = "init";
            break;
        case TokenId::CompilerFuncDrop:
            name = "drop";
            break;
        case TokenId::CompilerFuncMain:
            name = "main";
            break;
        case TokenId::CompilerFuncPreMain:
            name = "premain";
            break;
        case TokenId::CompilerFuncMessage:
            name = "message";
            break;
        default:
            name = "func";
            break;
    }

    auto& sym = SemaHelpers::registerUniqueSymbol<SymbolFunction>(sema, *this, name);
    sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));
    return Result::SkipChildren;
}

Result AstCompilerFunc::semaPreNode(Sema& sema)
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sym.setReturnTypeRef(sema.typeMgr().typeVoid());
    auto frame = sema.frame();
    frame.setCurrentFunction(&sym);
    sema.pushFramePopOnPostNode(frame);
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstCompilerRunExpr::semaPostNode(Sema& sema) const
{
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));

    auto&            ctx     = sema.ctx();
    const AstNodeRef nodeRef = sema.curNodeRef();
    SymbolFunction*  symFn   = nullptr;
    if (sema.hasSymbol(nodeRef))
    {
        symFn = &sema.symbolOf(nodeRef).cast<SymbolFunction>();
    }
    else
    {
        const SemaNodeView  nodeView(sema, nodeExprRef);
        const IdentifierRef idRef = SemaHelpers::getUniqueIdentifier(sema, "__run_expr");
        symFn                     = Symbol::make<SymbolFunction>(ctx, this, tokRef(), idRef, sema.frame().flagsForCurrentAccess());
        symFn->setOwnerSymMap(SemaFrame::currentSymMap(sema));
        symFn->setReturnTypeRef(nodeView.typeRef);
        symFn->setDeclared(ctx);
        symFn->setTyped(ctx);
        sema.setSymbol(nodeRef, symFn);

        const auto job = heapNew<CodeGenJob>(ctx, sema, *symFn, nodeRef);
        sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
    }

    RESULT_VERIFY(sema.waitCodeGenCompleted(symFn, codeRef()));

    const SemaNodeView nodeView(sema, nodeExprRef);

    MicroInstrBuilder& builder = symFn->microInstrBuilder(ctx);

    JITExecMemory executableMemory;
    RESULT_VERIFY(JIT::compile(ctx, builder, executableMemory));

    auto targetFn = executableMemory.entryPoint<void*>();
    SWC_ASSERT(targetFn != nullptr);

    const TypeInfo& nodeType         = *nodeView.type;
    TypeRef         resultStorageRef = nodeView.typeRef;
    if (nodeType.isEnum())
        resultStorageRef = nodeType.payloadSymEnum().underlyingTypeRef();
    else if (nodeType.isAlias())
        resultStorageRef = nodeType.payloadSymAlias().underlyingTypeRef();

    RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, nodeExprRef));
    const uint64_t         resultSize = sema.typeMgr().get(resultStorageRef).sizeOf(ctx);
    std::vector<std::byte> resultStorage(resultSize == 0 ? 1 : resultSize);
    const FFIReturn        returnValue = {
               .typeRef  = nodeView.typeRef,
               .valuePtr = resultStorage.data(),
    };
    FFI::call(ctx, targetFn, std::span<const FFIArgument>{}, returnValue);

    ConstantValue resultConstant;
    if (nodeType.isEnum())
    {
        ConstantValue     enumStorage    = ConstantValue::make(ctx, resultStorage.data(), resultStorageRef, ConstantValue::PayloadOwnership::Borrowed);
        const ConstantRef enumStorageRef = sema.cstMgr().addConstant(ctx, enumStorage);
        resultConstant                   = ConstantValue::makeEnumValue(ctx, enumStorageRef, nodeView.typeRef);
    }
    else
    {
        resultConstant = ConstantValue::make(ctx, resultStorage.data(), nodeView.typeRef, ConstantValue::PayloadOwnership::Borrowed);
    }

    sema.setConstant(nodeRef, sema.cstMgr().addConstant(ctx, resultConstant));
    return Result::Continue;
}

SWC_END_NAMESPACE();

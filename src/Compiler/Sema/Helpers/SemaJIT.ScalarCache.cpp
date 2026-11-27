#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.ScalarCache.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerCache.h"
#include "Main/CompilerCacheStore.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Sha256.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool appendScalarRunType(ByteArray& out, const TypeInfo& type)
    {
        if (!type.isBool() && !type.isInt())
            return false;
        out.appendLe32(static_cast<uint32_t>(type.kind()));
        out.appendLe32(type.flags().get());
        if (!type.isInt())
            return true;
        out.appendLe32(type.payloadIntBits());
        out.appendLe32(static_cast<uint32_t>(type.payloadIntSign()));
        return true;
    }

    bool appendScalarRunConstant(ByteArray& out, const SemaNodeView& view)
    {
        if (!view.hasConstant() || !view.hasType() || !appendScalarRunType(out, *view.type()))
            return false;
        const ConstantValue& value = *view.cst();
        if (value.isBool())
            out.appendLe64(value.getBool());
        else if (value.isInt())
        {
            const auto& number = value.getInt();
            out.appendLe32(number.bitWidth());
            if (number.bitWidth() <= 64)
                out.appendLe64(number.as64());
            else
            {
                const Utf8 digits = number.toString();
                out.appendLe32(static_cast<uint32_t>(digits.size()));
                out.append(digits.view());
            }
        }
        else
            return false;
        return true;
    }

    // Visit only the checked operations that can execute in this expression. Values,
    // bindings, and inlined scopes come from the current semantic graph. Everything
    // outside this subset, including pointer storage and foreign calls, uses the JIT.
    struct ScalarRunProof
    {
        ByteArray out;
        SmallVector<const AstNode*> active;
        SmallVector<const SemaInlinePayload*> inlines;
        SmallVector<SourceViewRef> sources;
        SmallVector<const SymbolVariable*> variables;
        uint32_t remaining = 512;

        bool call(Sema& sema, AstNodeRef ref, const SymbolFunction* owner, size_t inlineBase);

        bool source(Sema& sema, const AstNode& node)
        {
            const auto origin = node.codeRef();
            if (!origin.isValid())
                return false;
            const auto found = std::ranges::find(sources, origin.srcViewRef);
            out.appendLe32(static_cast<uint32_t>(found - sources.begin()));
            if (found == sources.end())
            {
                const SourceView& view = sema.srcView(origin.srcViewRef);
                if (!view.file() || view.file()->hasFlag(FileFlagsE::CustomSrc))
                    return false;
                const auto checksum = sha256(std::as_bytes(std::span{view.stringView()}));
                out.append(std::as_bytes(std::span{checksum}));
                sources.push_back(origin.srcViewRef);
            }
            out.appendLe32(origin.tokRef.get());
            return true;
        }

        void variableSlot(const SymbolVariable& variable)
        {
            const auto found = std::ranges::find(variables, &variable);
            out.appendLe32(static_cast<uint32_t>(found - variables.begin()));
            if (found == variables.end())
                variables.push_back(&variable);
        }

        bool localVariable(Sema& sema, const SymbolVariable* var, const SymbolFunction& owner, size_t inlineBase)
        {
            if (!var || var->hasExtraFlag(SymbolVariableFlagsE::GlobalStorage | SymbolVariableFlagsE::ClosureCapture) ||
                !var->typeRef().isValid() || !appendScalarRunType(out, sema.typeMgr().get(var->typeRef())))
                return false;
            for (const auto* expansion : inlines.span().subspan(inlineBase))
            {
                if (var == expansion->resultVar || std::ranges::find(expansion->localVariables, var) != expansion->localVariables.end())
                {
                    variableSlot(*var);
                    return true;
                }
            }
            if (!var->isFunctionLocalVariable(owner) && !owner.containsLocalVariable(*var) &&
                std::ranges::find(owner.parameters(), var) == owner.parameters().end())
                return false;
            variableSlot(*var);
            return true;
        }

        bool body(Sema& sema, AstNodeRef ref, const SymbolFunction& owner, size_t inlineBase)
        {
            if (!remaining || ref.isInvalid())
                return false;
            --remaining;
            // Codegen reads the original operand when a cast's substitution would
            // otherwise bring the walk back to the cast wrapping it.
            const auto resolved = sema.resolvedNodeRef(ref);
            if (resolved.isInvalid())
                return false;
            const auto mode = std::ranges::find(active, &sema.node(resolved)) != active.end() ?
                                  SemaNodeViewResolveE::Stored : SemaNodeViewResolveE::Resolved;
            const SemaNodeView view(sema, ref, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant, mode);
            const AstNode& node = *view.node();
            if (std::ranges::find(active, &node) != active.end())
                return false;
            active.push_back(&node);
            struct PopActive
            {
                SmallVector<const AstNode*>& active;
                SmallVector<const SemaInlinePayload*>& inlines;
                size_t inlineSize;
                ~PopActive() { active.pop_back(); inlines.resize(inlineSize); }
            } pop{active, inlines, inlines.size()};
            if (view.hasConstant())
            {
                out.appendLe32(0);
                return appendScalarRunConstant(out, view);
            }
            ref = view.nodeRef();
            out.appendLe32(static_cast<uint32_t>(node.id()) + 1);
            out.appendLe32(node.parserFlags());
            if (!source(sema, node))
                return false;
            const auto* expansion = sema.inlinePayload(ref);
            const bool inlineRoot = expansion && expansion->inlineRootRef == ref;
            out.appendLe32(inlineRoot);
            if (inlineRoot)
            {
                const auto* fn = expansion->sourceFunction;
                if (!fn || fn->attributes().hasMacroOrMixin() || fn->isFallible() || fn->isForeign() || expansion->returnsToCallerSite() ||
                    !expansion->returnTypeRef.isValid() || !appendScalarRunType(out, sema.typeMgr().get(expansion->returnTypeRef)))
                    return false;
                out.appendLe32(expansion->runtimeSafetyMask);
                out.appendLe32(expansion->callerRuntimeSafetyMask);
                out.appendLe32(expansion->sanityMask);
                fn->attributes().warnings.appendCacheIdentity(out);
                inlines.push_back(expansion);
                if (!localVariable(sema, expansion->resultVar, owner, inlineBase))
                    return false;
            }
            if (view.hasType() && !view.type()->isVoid())
            {
                out.appendLe32(1);
                if (!appendScalarRunType(out, *view.type()))
                    return false;
            }
            else
                out.appendLe32(0);

            SmallVector<AstNodeRef> children;
            switch (node.id())
            {
                case AstNodeId::FunctionBody:
                case AstNodeId::EmbeddedBlock:
                case AstNodeId::ScopeStmt:
                case AstNodeId::ReturnStmt:
                case AstNodeId::ParenExpr:
                case AstNodeId::ConditionalExpr:
                case AstNodeId::IfStmt:
                case AstNodeId::ElseStmt:
                case AstNodeId::LogicalExpr:
                case AstNodeId::RelationalExpr:
                    node.collectChildrenFromAst(children, sema.ast());
                    break;
                case AstNodeId::BinaryExpr:
                {
                    const auto& binary = node.cast<AstBinaryExpr>();
                    if (!Token::isOpArithmeticOrBitwise(sema.token(node.codeRef()).id))
                        return false;
                    out.appendLe32(binary.modifierFlags.get());
                    node.collectChildrenFromAst(children, sema.ast());
                    break;
                }
                case AstNodeId::AssignStmt:
                {
                    const auto& assign = node.cast<AstAssignStmt>();
                    if (!assign.nodeLeftRef.isValid() || !sema.node(assign.nodeLeftRef).is(AstNodeId::Identifier))
                        return false;
                    out.appendLe32(assign.modifierFlags.get());
                    node.collectChildrenFromAst(children, sema.ast());
                    break;
                }
                case AstNodeId::ForStmt:
                {
                    const auto& loop = node.cast<AstForStmt>();
                    if (loop.nodeWhereRef.isValid() || (loop.spanNamesRef.isValid() && sema.ast().spanSize(loop.spanNamesRef)) || loop.modifierFlags.get() || !loop.nodeExprRef.isValid())
                        return false;
                    node.collectChildrenFromAst(children, sema.ast());
                    break;
                }
                case AstNodeId::CastExpr:
                {
                    const auto& cast = node.cast<AstCastExpr>();
                    out.appendLe32(cast.modifierFlags.get());
                    children.push_back(cast.nodeExprRef);
                    break;
                }
                case AstNodeId::SingleVarDecl:
                {
                    const auto& decl = node.cast<AstSingleVarDecl>();
                    const SemaNodeView symbol(sema, ref, SemaNodeViewPartE::Symbol, mode);
                    const auto* named = symbol.singleSymbol();
                    if (!decl.nodeInitRef.isValid() || decl.storageFlags.get() ||
                        !localVariable(sema, named ? named->safeCast<SymbolVariable>() : nullptr, owner, inlineBase))
                        return false;
                    children.push_back(decl.nodeInitRef);
                    break;
                }
                case AstNodeId::Identifier:
                {
                    const SemaNodeView symView(sema, ref, SemaNodeViewPartE::Symbol, mode);
                    const auto* symbol = symView.singleSymbol();
                    const auto* var = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
                    if (!view.hasType() || !localVariable(sema, var, owner, inlineBase))
                        return false;
                    break;
                }
                case AstNodeId::CallExpr:
                    return call(sema, ref, &owner, inlineBase);
                case AstNodeId::IntrinsicCallExpr:
                    if (node.cast<AstIntrinsicCallExpr>().intrinsicId != TokenId::IntrinsicByteSwap)
                        return false;
                    node.cast<AstIntrinsicCallExpr>().collectArguments(children, sema.ast());
                    break;
                default:
                    return false;
            }
            out.appendLe32(static_cast<uint32_t>(children.size()));
            for (const AstNodeRef child : children)
            {
                if (!body(sema, child, owner, inlineBase))
                    return false;
            }
            return true;
        }
    };

    bool ScalarRunProof::call(Sema& caller, AstNodeRef callRef, const SymbolFunction* owner, const size_t inlineBase)
    {
        if (!remaining || caller.resolvedNodeRef(callRef) != callRef)
            return false;
        --remaining;
        const auto* callNode = caller.node(callRef).safeCast<AstCallExpr>();
        if (!callNode)
            return false;
        AstNodeRef callee = callNode->nodeExprRef;
        while (const auto* member = caller.node(callee).safeCast<AstMemberAccessExpr>())
        {
            const auto qualifier = caller.viewSymbol(member->nodeLeftRef);
            if (!qualifier.singleSymbol() || !qualifier.singleSymbol()->isNamespace())
                return false;
            callee = member->nodeRightRef;
        }
        if (!caller.node(callee).is(AstNodeId::Identifier))
            return false;
        const auto        view = caller.viewSymbol(callRef);
        const auto*       fn   = view.singleFunction();
        const auto*       decl = fn ? fn->declAs<AstFunctionDecl>() : nullptr;
        if (!decl || !fn->isSemaCompleted() || fn->isForeign() || fn->isFallible() || fn->isGenericInstance() || fn->isMethod() ||
            fn->attributes().hasMacroOrMixin() || fn->specOpKind() != SpecOpKind::None || !fn->returnTypeRef().isValid() || !decl->nodeBodyRef.isValid() ||
            !fn->ownerSymMap() || fn->ownerSymMap()->isFunction())
            return false;
        const auto& returnType = caller.typeMgr().get(fn->returnTypeRef());
        if (!appendScalarRunType(out, returnType))
            return false;

        SmallVector<ResolvedCallArgument> args;
        caller.appendResolvedCallArguments(callRef, args);
        if (args.size() != fn->parameters().size())
            return false;
        out.appendLe32(static_cast<uint32_t>(args.size()));
        for (size_t i = 0; i < args.size(); ++i)
        {
            const auto& arg = args[i];
            if (arg.argRef.isInvalid() || arg.passKind != CallArgumentPassKind::Direct || arg.defaultKind != CallArgumentDefaultKind::None ||
                arg.bindsReferenceToValue || arg.movesValueToParam || arg.isUfcsReceiver || arg.passUfcsAddressAsPointer || arg.typeInfoCstRef.isValid())
                return false;
            const TypeRef param = fn->parameters()[i]->typeRef();
            const auto argView = caller.viewTypeConstant(arg.argRef);
            if (param.isInvalid() || param != argView.typeRef() || !appendScalarRunType(out, caller.typeMgr().get(param)))
                return false;
            if (owner ? !body(caller, arg.argRef, *owner, inlineBase) : !appendScalarRunConstant(out, argView))
                return false;
        }

        std::unique_ptr<Sema> declHolder;
        Sema* functionSema = caller.tryCreateDeclSema(declHolder, fn->srcViewRef(), decl, fn->declNodeRef());
        if (!functionSema)
            functionSema = &caller;
        if (!functionSema->ast().tryFindNodeRef(decl).isValid())
            return false;
        const SourceFile* file = functionSema->file();
        if (!file || file->hasFlag(FileFlagsE::CustomSrc))
            return false;
        if (!source(*functionSema, *decl))
            return false;
        for (const auto* param : fn->parameters())
            variableSlot(*param);
        out.appendLe32(static_cast<uint32_t>(fn->callConvKind()));
        const auto& attr = fn->attributes();
        out.appendLe32(attr.effectiveRuntimeSafetyMask(caller.buildCfg().safetyGuards));
        out.appendLe32(attr.effectiveSanityMask(caller.buildCfg().sanityGuards));
        out.appendLe32(attr.rtFlags.get());
        attr.warnings.appendCacheIdentity(out);
        return body(*functionSema, decl->nodeBodyRef, *fn, inlines.size());
    }

    std::array<uint8_t, 32> scalarRunChecksum(const Utf8& key, std::span<const std::byte> bytes)
    {
        return sha256Parts({std::as_bytes(std::span{key.view()}), bytes});
    }

    bool appendRuntimeInputs(ByteArray& identity, const CompilerInstance& compiler)
    {
        auto files = compiler.files();
        std::erase_if(files, [](const SourceFile* file) { return !file->isRuntime(); });
        std::ranges::sort(files, {}, &SourceFile::genericPathString);
        identity.appendLe32(static_cast<uint32_t>(files.size()));
        for (const SourceFile* file : files)
        {
            if (!file->ast().hasSourceView())
                return false;
            const auto checksum = compiler.sourceFileChecksum(*file);
            identity.append(std::as_bytes(std::span{checksum}));
        }
        return !files.empty();
    }

}

namespace SemaJIT::ScalarCache
{
    Utf8 buildKey(Sema& sema, const SymbolFunction& evaluator, AstNodeRef ref, const TypeRef resultType)
    {
        const auto& command = sema.ctx().cmdLine();
        if (sema.compiler().isModuleSetupMode() || sema.compiler().jitHasUntrackedEffects() ||
            !sema.node(ref).is(AstNodeId::CallExpr) || command.optimizerStats || sema.buildCfgBackend().debugInfo || compilerCacheIdentity().empty())
            return {};
#if SWC_DEV_MODE
        if (command.devFull || command.validateMicro)
            return {};
#endif
        ScalarRunProof proof;
        proof.out.append("checked scalar run v1");
        proof.out.appendLe32(static_cast<uint32_t>(command.targetOs));
        proof.out.appendLe32(static_cast<uint32_t>(command.targetArch));
        proof.out.appendLe64(command.targetCpu.size());
        proof.out.append(command.targetCpu.view());
        sema.buildCfgBackend().appendCacheIdentity(proof.out);
        command.warningPolicy.appendCacheIdentity(proof.out);
        sema.compiler().warningPolicy().appendCacheIdentity(proof.out);
        proof.out.appendLe32(evaluator.attributes().effectiveRuntimeSafetyMask(sema.buildCfg().safetyGuards));
        proof.out.appendLe32(evaluator.attributes().effectiveSanityMask(sema.buildCfg().sanityGuards));
        evaluator.attributes().warnings.appendCacheIdentity(proof.out);
        if (!appendScalarRunType(proof.out, sema.typeMgr().get(resultType)))
            return {};
        const bool valid = sema.resolvedNodeRef(ref) == ref ? proof.call(sema, ref, nullptr, 0) : proof.body(sema, ref, evaluator, 0);
        if (!valid || !appendRuntimeInputs(proof.out, sema.compiler()))
            return {};
        return Utf8Helper::toLowerHex(sha256(proof.out.span()));
    }

    bool read(std::span<std::byte> value, const Utf8& key)
    {
        const auto record = CompilerCacheStore::get().read(key);
        if (!record || record.bytes.size() != value.size() + 32)
            return false;
        const auto bytes = record.bytes.span().first(value.size());
        const auto checksum = scalarRunChecksum(key, bytes);
        if (std::memcmp(checksum.data(), record.bytes.data() + value.size(), checksum.size()))
            return false;
        std::ranges::copy(bytes, value.begin());
        return true;
    }

    void write(const Utf8& key, const std::span<const std::byte> value)
    {
        const auto checksum = scalarRunChecksum(key, value);
        ByteArray record;
        record.append(value);
        record.append(std::as_bytes(std::span{checksum}));
        CompilerCacheStore::get().write(key, std::move(record));
    }
}

SWC_END_NAMESPACE();

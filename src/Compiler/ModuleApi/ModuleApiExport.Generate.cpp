#include "pch.h"
#include "Backend/Runtime.h"
#include "Compiler/ModuleApi/ModuleApiExport.Internal.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using ModuleApiExport::appendGeneratedRootUnique;
    using ModuleApiExport::buildModuleNamespaceName;
    using ModuleApiExport::buildSanitizedModuleApiSnippet;
    using ModuleApiExport::extractPublicNamespacePath;
    using ModuleApiExport::findExportDeclRoot;
    using ModuleApiExport::isCurrentModuleSourceFile;
    using ModuleApiExport::isCurrentModuleSymbol;
    using ModuleApiExport::isExportedPublicDeclScope;
    using ModuleApiExport::isModuleApiOpaqueType;
    using ModuleApiExport::isWholeFileExportedSymbol;
    using ModuleApiExport::ModuleApiGeneratedRoot;
    using ModuleApiExport::moduleApiNodeSourceView;
    using ModuleApiExport::moduleApiSnippetStartTokRef;
    using ModuleApiExport::removeModuleApiAttributes;
    using ModuleApiExport::sameNamespacePath;
    using ModuleApiExport::tryBuildImplPrefix;
    using ModuleApiExport::tryFindReachableNodeRef;
    using ModuleApiExport::tryGetModuleApiSnippet;
    using ModuleApiExport::tryGetModuleApiSnippetOffsets;
    using ModuleApiExport::tryGetModuleApiSnippetStartOffset;

    Result buildSanitizedRootSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, std::string_view eol);
    void   collectMissingFunctionAttributes(SmallVector<Utf8>& ioAttributes, const SymbolFunction& symbolFunction, bool hasExportedBody, const Utf8& snippet);

    bool supportsGeneratedModuleApiForeignFunctions(const CompilerInstance& compiler)
    {
        switch (compiler.buildCfg().backendKind)
        {
            case Runtime::BuildCfgBackendKind::StaticLibrary:
            case Runtime::BuildCfgBackendKind::SharedLibrary:
                return true;

            default:
                return false;
        }
    }

    bool isExportedBodySymbolAvailable(TaskContext& ctx, const SymbolFunction& function, const Symbol& symbol)
    {
        // Namespace paths are reconstructed around the generated declarations, independently
        // of the access recorded on the namespace symbol itself.
        if (symbol.isNamespace())
            return true;

        // Parameters also occur in inlined bodies. Their implicit 'me' has no source
        // declaration, but is reconstructed with the function that owns it.
        if (const auto* variable = symbol.safeCast<SymbolVariable>())
        {
            if (variable->hasExtraFlag(SymbolVariableFlagsE::Parameter) || variable->isFunctionLocalVariable(function) || function.containsLocalVariable(*variable))
                return true;
        }
        if (!isCurrentModuleSymbol(ctx.compiler(), symbol) || isWholeFileExportedSymbol(ctx.compiler(), symbol))
            return true;

        // A field, a member constant and an enum value travel with the type that declares them,
        // and the body is re-emitted in that same generated file, so it reads them exactly as it
        // did in the module it came from: the access rules answer with the file the code was
        // written in, not with the one that ends up calling it. An opaque type publishes storage
        // instead of members, so nothing a body names inside one can bind again.
        if (symbol.isValueExpr())
        {
            bool ownedByExportedType = false;
            for (const SymbolMap* owner = symbol.ownerSymMap(); owner; owner = owner->ownerSymMap())
            {
                if (!owner->isStruct() && !owner->isEnum())
                    continue;
                if (!owner->isPublic() || isModuleApiOpaqueType(*owner))
                    return false;

                ownedByExportedType = true;
            }

            if (ownedByExportedType)
                return true;
        }

        return symbol.isPublic();
    }

    Result reportFunctionBodyExportError(TaskContext& ctx, const SymbolFunction& function, const SourceCodeRange& range, std::string_view because, DiagnosticId diagnosticId, const Symbol* referencedSymbol = nullptr)
    {
        Diagnostic diag = Diagnostic::get(diagnosticId, ctx.compiler().srcView(function.srcViewRef()).fileRef());
        diag.addArgument(Diagnostic::ARG_SYM, function.getFullScopedName(ctx));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
        diag.last().addSpan(range, "", DiagnosticSeverity::Error);
        if (referencedSymbol)
        {
            diag.addNote(DiagnosticId::cmd_note_api_dependency_declared_here);
            diag.last().addArgument(Diagnostic::ARG_TARGET, referencedSymbol->getFullScopedName(ctx));
            diag.last().addSpan(referencedSymbol->codeRange(ctx));
        }
        diag.report(ctx);
        return Result::Error;
    }

    Result validateExportedFunctionBody(TaskContext& ctx, const SourceFile& file, const SymbolFunction& function, DiagnosticId diagnosticId)
    {
        const auto* functionDecl = function.decl() ? function.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!functionDecl || functionDecl->nodeBodyRef.isInvalid())
            return reportFunctionBodyExportError(ctx, function, function.codeRange(ctx), "the function has no body", diagnosticId);

        Result     result = Result::Continue;
        const Ast& ast    = file.ast();
        Ast::visit(ast, functionDecl->nodeBodyRef, [&](const AstNodeRef nodeRef, const AstNode& node) {
            const NodePayload::ResolvedSymbols resolved    = file.nodePayloadContext().resolveSymbols(nodeRef);
            const Symbol*                      unavailable = nullptr;
            for (const Symbol* symbol : resolved.symbols)
            {
                if (symbol && !isExportedBodySymbolAvailable(ctx, function, *symbol))
                {
                    unavailable = symbol;
                    break;
                }
            }

            // A conversion can fold a named constant in place; the body still spells its name.
            if (!unavailable)
            {
                const Symbol* folded = file.nodePayloadContext().foldedSourceSymbol(nodeRef);
                if (folded && !isExportedBodySymbolAvailable(ctx, function, *folded))
                    unavailable = folded;
            }

            if (unavailable)
            {
                const AstNode& focus   = node.is(AstNodeId::CallExpr) ? ast.node(node.cast<AstCallExpr>().nodeExprRef) : node;
                const Utf8     because = std::format("symbol '{}' is not exposed by the module API", unavailable->getFullScopedName(ctx));
                result                 = reportFunctionBodyExportError(ctx, function, focus.codeRange(ctx), because.view(), diagnosticId, unavailable);
                return Ast::VisitResult::Stop;
            }

            return Ast::VisitResult::Continue;
        });
        return result;
    }

    bool tryGetSwagAttributeIntValue(uint32_t& outValue, TaskContext& ctx, const Symbol& symbol, std::string_view attrName)
    {
        outValue = 0;
        for (const AttributeInstance& attribute : symbol.attributes().attributes)
        {
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != attrName)
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isInt())
                    continue;

                outValue = static_cast<uint32_t>(cst.getInt().as64());
                return true;
            }
        }

        return false;
    }

    // Whether the snippet already spells `marker` as an attribute.
    //
    // The snippet is source text, so a plain substring search also matches an identifier that
    // happens to contain the attribute name, and a function named 'depDiscardableCount' would
    // then lose its '#[Swag.Discardable]'. Only a spelling bounded like a member of an
    // attribute list counts: '#[Inline]', '#[Swag.Inline]', or either inside a list.
    bool snippetSpellsAttribute(const std::string_view snippet, const std::string_view marker)
    {
        for (size_t pos = snippet.find(marker); pos != std::string_view::npos; pos = snippet.find(marker, pos + 1))
        {
            const size_t after  = pos + marker.size();
            const char   before = pos == 0 ? '\0' : snippet[pos - 1];
            const char   next   = after >= snippet.size() ? '\0' : snippet[after];
            if ((before == '[' || before == '.' || before == ' ' || before == ',') && (next == ']' || next == ',' || next == '('))
                return true;
        }

        return false;
    }

    // The generated API opens with the runtime prelude in scope, which is what lets a copied
    // '#[Inline]' resolve, so every attribute the generator writes is spelled unqualified too.
    void appendMissingFunctionAttribute(SmallVector<Utf8>& ioAttributes, const SymbolFunction& symbolFunction, const std::string_view snippet, const RtAttributeFlagsE flag, const std::string_view marker)
    {
        if (!symbolFunction.attributes().hasRtFlag(flag))
            return;
        if (snippetSpellsAttribute(snippet, marker))
            return;

        ioAttributes.push_back(Utf8{marker});
    }

    // One list holds every attribute of a declaration, so an entry costs one line whatever it
    // states.
    Utf8 buildAttributeListLine(std::span<const Utf8> attributes, const std::string_view eol)
    {
        if (attributes.empty())
            return {};

        Utf8 result = "#[";
        for (size_t index = 0; index < attributes.size(); ++index)
        {
            if (index != 0)
                result += ", ";
            result += attributes[index];
        }

        result += "]";
        result += eol;
        return result;
    }

    AstNodeRef moduleApiOpaqueTypeBodyRef(const AstNode& declNode)
    {
        if (declNode.is(AstNodeId::StructDecl))
            return declNode.cast<AstStructDecl>().nodeBodyRef;
        if (declNode.is(AstNodeId::UnionDecl))
            return declNode.cast<AstUnionDecl>().nodeBodyRef;
        return AstNodeRef::invalid();
    }

    bool tryBuildOpaqueTypePrefix(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        if (!root.file || !root.symbol || !root.symbol->decl())
            return false;

        const AstNode&   declNode = *root.symbol->decl();
        const AstNodeRef bodyRef  = moduleApiOpaqueTypeBodyRef(declNode);
        if (bodyRef.isInvalid())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, *root.file, root.nodeRef, startOffset, endOffset))
            return false;

        const Ast& ast = root.file->ast();
        if (!ast.hasSourceView() || ast.isAdditionalNode(bodyRef))
            return false;

        const AstNode& bodyNode = ast.node(bodyRef);
        if (!bodyNode.tokRef().isValid())
            return false;

        const SourceView&      srcView         = moduleApiNodeSourceView(ctx, ast, root.nodeRef);
        const uint32_t         bodyStartOffset = srcView.tokenByteStart(srcView.token(bodyNode.tokRef()));
        const std::string_view source          = srcView.stringView();
        if (bodyStartOffset <= startOffset || bodyStartOffset > source.size())
            return false;

        std::string_view prefixText = source.substr(startOffset, bodyStartOffset - startOffset);
        while (!prefixText.empty() && std::isspace(static_cast<unsigned char>(prefixText.back())))
            prefixText.remove_suffix(1);

        outPrefix = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, prefixText, eol);
        return !outPrefix.empty();
    }

    struct OpaqueStringSlot
    {
        uint64_t        offset = 0;
        Runtime::String value;
    };

    bool collectOpaqueStringSlots(TaskContext& ctx, SmallVector<OpaqueStringSlot>& slots, TypeRef typeRef, std::span<const std::byte> bytes, uint64_t baseOffset)
    {
        typeRef              = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isString())
        {
            OpaqueStringSlot slot;
            slot.offset = baseOffset;
            SWC_ASSERT(bytes.size() == sizeof(slot.value));
            std::memcpy(&slot.value, bytes.data(), sizeof(slot.value));
            slots.push_back(slot);
            return true;
        }
        if (type.isArray())
        {
            const TypeRef  elementType = type.payloadArrayElemTypeRef();
            const uint64_t elementSize = ctx.typeMgr().get(elementType).sizeOf(ctx);
            SWC_ASSERT(elementSize);
            for (uint64_t offset = 0; offset < bytes.size(); offset += elementSize)
            {
                if (!collectOpaqueStringSlots(ctx, slots, elementType, bytes.subspan(offset, elementSize), baseOffset + offset))
                    return false;
            }
            return true;
        }
        if (type.isStruct())
        {
            const SymbolStruct& owner = type.payloadSymStruct();
            if (owner.hasDynamicStorage())
                return false;
            // A union has no active-field tag from which to recover a non-null pointer.
            // Scalar representations and null pointer slots can still stay constant.
            if (owner.isUnion())
            {
                SmallVector<OpaqueStringSlot> unionSlots;
                for (const SymbolVariable* field : owner.fields())
                {
                    const uint64_t size = field->typeInfo(ctx).sizeOf(ctx);
                    if (!collectOpaqueStringSlots(ctx, unionSlots, field->typeRef(), bytes.subspan(field->offset(), size), baseOffset + field->offset()))
                        return false;
                }
                return std::ranges::none_of(unionSlots, [](const OpaqueStringSlot& slot) { return slot.value.ptr != nullptr; });
            }
            for (const SymbolVariable* field : owner.fields())
            {
                const uint64_t size = field->typeInfo(ctx).sizeOf(ctx);
                if (!collectOpaqueStringSlots(ctx, slots, field->typeRef(), bytes.subspan(field->offset(), size), baseOffset + field->offset()))
                    return false;
            }
            return true;
        }
        // A non-null address can name provider state, a function, reflected metadata,
        // or another allocation. Never turn that address into integer initializer bytes.
        return !type.isPointerLike() || std::ranges::all_of(bytes, [](std::byte value) { return value == std::byte{0}; });
    }

    void appendOpaqueByteStorageRange(Utf8& result, std::span<const std::byte> bytes, uint64_t offset, std::string_view eol)
    {
        if (bytes.empty())
            return;
        result += std::format("    internal swagOpaqueStorage{}: [{}] u8", offset, bytes.size());
        if (std::ranges::any_of(bytes, [](std::byte value) { return value != std::byte{0}; }))
        {
            result += " = [";
            for (size_t i = 0; i < bytes.size(); ++i)
            {
                if (i)
                    result += ", ";
                result += std::format("{}", std::to_integer<uint8_t>(bytes[i]));
            }
            result += "]";
        }
        result += eol;
    }

    void appendOpaqueByteStorage(Utf8& result, std::span<const std::byte> bytes, uint64_t offset, std::string_view eol)
    {
        // Long zero runs need storage, not thousands of literal elements. Keep short
        // gaps inside their surrounding range so sparse defaults do not create a field
        // for each zero byte in a scalar's representation.
        constexpr size_t MIN_ZERO_RUN = 64;
        size_t           rangeStart   = 0;
        size_t           cursor       = 0;
        while (cursor < bytes.size())
        {
            if (bytes[cursor] != std::byte{0})
            {
                ++cursor;
                continue;
            }
            const size_t zeroStart = cursor;
            while (cursor < bytes.size() && bytes[cursor] == std::byte{0})
                ++cursor;
            if (cursor - zeroStart < MIN_ZERO_RUN)
                continue;

            appendOpaqueByteStorageRange(result, bytes.subspan(rangeStart, zeroStart - rangeStart), offset + rangeStart, eol);
            appendOpaqueByteStorageRange(result, bytes.subspan(zeroStart, cursor - zeroStart), offset + zeroStart, eol);
            rangeStart = cursor;
        }
        appendOpaqueByteStorageRange(result, bytes.subspan(rangeStart), offset + rangeStart, eol);
    }

    void appendOpaqueStringStorage(Utf8& result, const OpaqueStringSlot& slot, std::string_view eol)
    {
        result += std::format("    internal swagOpaqueString{}: string", slot.offset);
        if (!slot.value.ptr)
            result += "? = null";
        else
        {
            result += " = \"";
            for (const unsigned char value : std::string_view{slot.value.ptr, slot.value.length})
            {
                if (value == '"' || value == '\\')
                {
                    result += '\\';
                    result += static_cast<char>(value);
                }
                else if (value < 0x20 || value == 0x7f)
                    result += std::format("\\x{:02x}", value);
                else
                    result += static_cast<char>(value);
            }
            result += '"';
        }
        result += eol;
    }

    Result buildOpaqueDefaultStorage(TaskContext& ctx, Utf8& outFields, bool& needsRuntimeDefault, const ModuleApiGeneratedRoot& root, std::string_view eol)
    {
        auto& owner = const_cast<SymbolStruct&>(root.symbol->cast<SymbolStruct>());
        Sema  sema{ctx, const_cast<SourceFile*>(root.file)->nodePayloadContext(), root.nodeRef, false};
        owner.computeImplicitDefaultFlags(sema);
        if (owner.hasDynamicStorage())
        {
            needsRuntimeDefault = true;
            return Result::Continue;
        }
        ConstantRef defaultRef = ConstantRef::invalid();
        SWC_RESULT(owner.computeDefaultValue(sema, owner.typeRef(), defaultRef));
        needsRuntimeDefault = defaultRef.isInvalid();
        if (needsRuntimeDefault)
            return Result::Continue;

        const ConstantValue&          constant = ctx.cstMgr().get(defaultRef);
        const auto                    bytes    = constant.getStruct();
        SmallVector<OpaqueStringSlot> slots;
        needsRuntimeDefault = !collectOpaqueStringSlots(ctx, slots, owner.typeRef(), bytes, 0);
        if (needsRuntimeDefault)
            return Result::Continue;
        std::ranges::sort(slots, {}, &OpaqueStringSlot::offset);

        // The typed slots are also the relocation inventory. If a representation carries
        // another relocation, preserve it through the provider instead of copying its address.
        const DataSegmentRef dataRef = constant.dataSegmentRef();
        if (dataRef.isValid())
        {
            std::vector<DataSegmentRelocation> relocations;
            ctx.cstMgr().shardDataSegment(dataRef.shardIndex).copyRelocations(relocations, dataRef.offset, static_cast<uint32_t>(bytes.size()));
            for (const DataSegmentRelocation& relocation : relocations)
            {
                const uint64_t offset = relocation.offset - dataRef.offset;
                if (relocation.kind != DataSegmentRelocationKind::DataSegmentOffset ||
                    std::ranges::none_of(slots, [offset](const OpaqueStringSlot& slot) { return slot.offset + offsetof(Runtime::String, ptr) == offset; }))
                {
                    needsRuntimeDefault = true;
                    return Result::Continue;
                }
            }
        }

        uint64_t cursor = 0;
        for (const OpaqueStringSlot& slot : slots)
        {
            if (slot.offset < cursor)
            {
                needsRuntimeDefault = true;
                outFields.clear();
                return Result::Continue;
            }
            appendOpaqueByteStorage(outFields, bytes.subspan(cursor, slot.offset - cursor), cursor, eol);
            appendOpaqueStringStorage(outFields, slot, eol);
            cursor = slot.offset + sizeof(Runtime::String);
        }
        appendOpaqueByteStorage(outFields, bytes.subspan(cursor), cursor, eol);
        return Result::Continue;
    }

    struct OpaqueForeignMethod
    {
        const SymbolFunction* function = nullptr;
        std::string_view      name;
        bool                  implicit = false;
    };

    void appendOpaqueForeignMethod(TaskContext& ctx, Utf8& result, const OpaqueForeignMethod& method, std::string_view eol)
    {
        SWC_ASSERT(method.function);
        SmallVector<Utf8> attributes;
        attributes.push_back(Utf8{std::format("Foreign(function: \"{}\")", method.function->computePublicApiSymbolName(ctx))});
        collectMissingFunctionAttributes(attributes, *method.function, false, {});
        const auto implicitAttribute = std::ranges::find(attributes, "Implicit");
        if (implicitAttribute != attributes.end())
            attributes.erase(implicitAttribute);
        if (method.implicit)
            attributes.push_back("Implicit");
        result += "    ";
        result += buildAttributeListLine(attributes.span(), eol);
        result += "    private mtd ";
        result += method.name;
        result += "()";
        result += eol;
    }

    struct OpaqueLifecycleOperation
    {
        SpecOpKind            kind;
        const SymbolFunction* effective = nullptr;
        const SymbolFunction* direct    = nullptr;
    };

    Result buildOpaqueTypeSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        const auto* symbolStruct = root.symbol ? root.symbol->safeCast<SymbolStruct>() : nullptr;
        if (!symbolStruct)
            return Result::Continue;

        Utf8 fields;
        bool needsRuntimeDefault = false;
        SWC_RESULT(buildOpaqueDefaultStorage(ctx, fields, needsRuntimeDefault, root, eol));
        const OpaqueLifecycleOperation operations[] = {
            {SpecOpKind::OpDrop, symbolStruct->effectiveOpDrop(ctx), symbolStruct->opDrop()},
            {SpecOpKind::OpPostCopy, symbolStruct->effectiveOpPostCopy(ctx), symbolStruct->opPostCopy()},
            {SpecOpKind::OpPostMove, symbolStruct->effectiveOpPostMove(ctx), symbolStruct->opPostMove()},
        };
        const bool hasLifecycle = std::ranges::any_of(operations, [](const OpaqueLifecycleOperation& operation) { return operation.effective != nullptr; });

        Utf8 prefix;
        if (!tryBuildOpaqueTypePrefix(ctx, root, eol, prefix))
        {
            prefix += "#[Swag.Opaque]";
            prefix += eol;
            prefix += symbolStruct->isUnion() ? "union " : "struct ";
            prefix += symbolStruct->name(ctx);
        }

        static constexpr std::string_view MATERIALIZED_LAYOUT_ATTRIBUTES[] = {"Pack", "Opaque"};
        removeModuleApiAttributes(ctx, prefix, MATERIALIZED_LAYOUT_ATTRIBUTES);

        Utf8       result;
        const bool requiresExplicitInit = symbolStruct->requiresExplicitInitialization();
        if (requiresExplicitInit)
        {
            result += "#[Swag.Opaque(requiresInit: true)]";
            result += eol;
        }
        else if (needsRuntimeDefault)
        {
            result += "#[Swag.Opaque(runtimeDefault: true)]";
            result += eol;
        }
        else
        {
            result += "#[Swag.Opaque]";
            result += eol;
        }
        if (!TypeGen::lifecycleFlagsOfTypeRef(ctx, symbolStruct->typeRef()).canCopy && !snippetSpellsAttribute(prefix.view(), "NoCopy"))
        {
            result += "#[NoCopy]";
            result += eol;
        }
        // Typed relocation slots and byte spans must retain the provider's exact offsets.
        result += "#[Pack(1)]";
        result += eol;
        uint32_t alignValue = 0;
        if (symbolStruct->alignment() > 1 && !tryGetSwagAttributeIntValue(alignValue, ctx, *symbolStruct, "Align"))
        {
            result += std::format("#[Align({})]", symbolStruct->alignment());
            result += eol;
        }

        result += prefix;
        if (!result.empty() && result.back() != ' ' && result.back() != '\t')
            result += ' ';
        result += "{";
        result += eol;
        if (needsRuntimeDefault)
        {
            result += "    internal swagOpaqueStorage: [";
            result += std::format("{}", symbolStruct->sizeOf());
            result += "] u8";
            result += eol;
        }
        else if (symbolStruct->isUnion() && !fields.empty())
        {
            // A union must keep one storage field: sibling segments would all overlap
            // at offset zero. Serializable union spans contain bytes only, so this
            // anonymous struct has alignment one and preserves their exact offsets.
            result += "    internal swagOpaqueStorage: struct";
            result += eol;
            result += "    {";
            result += eol;
            const std::string_view fieldText = fields.view();
            size_t                 cursor    = 0;
            while (cursor < fieldText.size())
            {
                const size_t end  = fieldText.find('\n', cursor);
                const size_t next = end == std::string_view::npos ? fieldText.size() : end + 1;
                result += "    ";
                result += fieldText.substr(cursor, next - cursor);
                cursor = next;
            }
            result += "    }";
            result += eol;
        }
        else
            result += fields;
        result += "}";
        if (hasLifecycle || (needsRuntimeDefault && !requiresExplicitInit))
        {
            result += eol;
            result += "impl ";
            result += symbolStruct->name(ctx);
            result += eol;
            result += "{";
            result += eol;
            if (!requiresExplicitInit)
            {
                const SymbolFunction* initFunction = symbolStruct->effectiveOpInit(ctx);
                SWC_ASSERT(initFunction);
                if (needsRuntimeDefault)
                    appendOpaqueForeignMethod(ctx, result, {initFunction, "swagOpaqueInit", true}, eol);
                // An imported lifecycle wrapper suppresses local wrapper generation. Keep
                // reflection initialization available even for a serialized constant default.
                if (hasLifecycle || symbolStruct->isUnion())
                    appendOpaqueForeignMethod(ctx, result, {initFunction, SemaSpecOp::generatedInitWrapperName(), true}, eol);
            }
            for (const OpaqueLifecycleOperation& operation : operations)
            {
                if (!operation.effective)
                    continue;
                appendOpaqueForeignMethod(ctx, result, {operation.effective, SemaSpecOp::generatedLifecycleWrapperName(operation.kind), true}, eol);
                // Public direct operations retain their original targets for explicit calls.
                // Otherwise a private special operation preserves lifecycle classification;
                // automatic dispatch selects the complete implicit provider wrapper above.
                if (!operation.direct || !operation.direct->isPublic())
                    appendOpaqueForeignMethod(ctx, result, {operation.effective, SemaSpecOp::specOpFunctionName(operation.kind), false}, eol);
            }
            result += "}";
        }
        outSnippet = result;
        return Result::Continue;
    }

    bool isGeneratedModuleApiSourceFunction(TaskContext& ctx, const SymbolFunction& symbolFunction)
    {
        if (!symbolFunction.isPublic())
            return false;
        if (!symbolFunction.decl() || symbolFunction.decl()->isNot(AstNodeId::FunctionDecl))
            return false;
        if (symbolFunction.attributes().hasRtFlag(RtAttributeFlagsE::PlaceHolder))
            return false;
        if (symbolFunction.supportsPublicApiForeignExport() && supportsGeneratedModuleApiForeignFunctions(ctx.compiler()))
            return false;

        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbolFunction);
        if (!sourceFile || !isCurrentModuleSourceFile(*sourceFile))
            return false;

        AstNodeRef declRef;
        if (!tryFindReachableNodeRef(sourceFile->ast(), symbolFunction.decl(), declRef))
            return false;
        return isExportedPublicDeclScope(*sourceFile, declRef, symbolFunction);
    }

    bool hasGeneratedModuleApiSourceMethod(TaskContext& ctx, const SymbolStruct& symbolStruct)
    {
        for (const SymbolFunction* method : symbolStruct.declaredMethods())
        {
            if (method && isGeneratedModuleApiSourceFunction(ctx, *method))
                return true;
        }

        return false;
    }

    void trimTrailingModuleApiWhitespace(Utf8& text)
    {
        while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back())))
            text.pop_back();
    }

    void trimTrailingModuleApiDeclarationSeparator(Utf8& text)
    {
        trimTrailingModuleApiWhitespace(text);
        if (!text.empty() && text.back() == ';')
            text.pop_back();
        trimTrailingModuleApiWhitespace(text);
    }

    void collectMissingFunctionAttributes(SmallVector<Utf8>& ioAttributes, const SymbolFunction& symbolFunction, const bool hasExportedBody, const Utf8& snippet)
    {
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Macro, "Macro");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Mixin, "Mixin");

        // 'Inline' asks the consumer to expand the body, so it only means something where the
        // body travels with the declaration. Publishing it on an entry the API reduced to a
        // foreign call promises an expansion that cannot happen.
        if (hasExportedBody)
            appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Inline, "Inline");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::ConstExpr, "ConstExpr");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::ReadOnly, "ReadOnly");
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Implicit, "Implicit");
        if (!hasExportedBody && symbolFunction.hasFullInitialization() && !snippetSpellsAttribute(snippet.view(), "FullInit"))
            ioAttributes.push_back("FullInit");

        // 'Discardable' is a fact about the call site, not about the body: without it an
        // importer has to write 'discard' where a caller inside the module does not.
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::Discardable, "Discardable");

        // So is 'NoReturn': an importer judges the flow after the call by it.
        appendMissingFunctionAttribute(ioAttributes, symbolFunction, snippet.view(), RtAttributeFlagsE::NoReturn, "NoReturn");

        // The borrow summaries are computed facts, not source attributes: re-emit them
        // so importers can judge their call sites against this function's parameters.
        // The export runs after the final sema drain, so the masks include the
        // transitive bits added by the summary fixpoint.
        const uint64_t returnsMask         = symbolFunction.returnBorrowsParamsMask();
        const uint64_t storesMask          = symbolFunction.storesParamsMask();
        const uint64_t intoPairs           = symbolFunction.storesIntoParamPairs();
        const uint64_t freesMask           = symbolFunction.freesParamsMask();
        const uint64_t reallocatesMask     = symbolFunction.reallocatesParamsMask();
        const uint64_t returnsPayloadMask  = symbolFunction.returnsPayloadParamsMask();
        const uint64_t returnsStorageMask  = symbolFunction.returnsStorageParamsMask();
        const uint64_t returnsIndirectMask = symbolFunction.returnsIndirectParamsMask();
        const uint64_t storesIndirectMask  = symbolFunction.storesIndirectParamsMask();
        const uint64_t intoIndirectPairs   = symbolFunction.storesIndirectIntoParamPairs();
        if ((returnsMask != 0 || storesMask != 0 || intoPairs != 0 || freesMask != 0 || reallocatesMask != 0 || returnsPayloadMask != 0 || returnsIndirectMask != 0 || storesIndirectMask != 0 || intoIndirectPairs != 0 || !symbolFunction.observesExternalBorrows()) &&
            (!hasExportedBody || !snippetSpellsAttribute(snippet.view(), "BorrowSummary")))
        {
            Utf8 summary{std::format("BorrowSummary({}, {}, {}, {}, {}, {}, {}, observesExternal: {}", returnsMask, storesMask, intoPairs, freesMask, reallocatesMask, returnsPayloadMask, returnsStorageMask, symbolFunction.observesExternalBorrows())};
            if (returnsIndirectMask)
                summary += std::format(", returnsIndirect: {}", returnsIndirectMask);
            if (storesIndirectMask)
                summary += std::format(", storesIndirect: {}", storesIndirectMask);
            if (intoIndirectPairs)
                summary += std::format(", intoIndirect: {}", intoIndirectPairs);
            summary += ")";
            ioAttributes.push_back(std::move(summary));
        }
    }

    void prependMissingFunctionAttributes(const SymbolFunction& symbolFunction, const std::string_view eol, const bool hasExportedBody, Utf8& ioSnippet)
    {
        SmallVector<Utf8> attributes;
        collectMissingFunctionAttributes(attributes, symbolFunction, hasExportedBody, ioSnippet);

        const Utf8 line = buildAttributeListLine(attributes.span(), eol);
        if (!line.empty())
            ioSnippet = line + ioSnippet;
    }

    bool tryFindFunctionBodyStartOffset(const ModuleApiGeneratedRoot& root, uint32_t& outBodyStartOffset)
    {
        outBodyStartOffset         = 0;
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction || !root.file || !symbolFunction->decl())
            return false;

        const Ast& ast = root.file->ast();
        if (!ast.hasSourceView() || root.nodeRef.isInvalid())
            return false;

        const auto* functionDecl = symbolFunction->decl()->safeCast<AstFunctionDecl>();
        if (!functionDecl)
            return false;

        const TokenRef bodyTokRef = ModuleApi::moduleApiFunctionBodyStartTokRef(ast, *functionDecl);
        if (!bodyTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();
        outBodyStartOffset        = srcView.tokenByteStart(srcView.token(bodyTokRef));
        return true;
    }

    TokenRef moduleApiFunctionParamsEndTokRef(const Ast& ast, const AstFunctionDecl& functionDecl)
    {
        if (!functionDecl.nodeParamsRef.isValid() || ast.isAdditionalNode(functionDecl.nodeParamsRef))
            return TokenRef::invalid();

        const AstNode& paramsNode  = ast.node(functionDecl.nodeParamsRef);
        TokenRef       startTokRef = moduleApiSnippetStartTokRef(ast, paramsNode);
        if (!startTokRef.isValid())
            startTokRef = paramsNode.tokRef();

        const TokenRef endTokRef = paramsNode.tokRefEnd(ast);
        if (!endTokRef.isValid())
            return TokenRef::invalid();
        if (!ast.hasSourceView() || !startTokRef.isValid())
            return endTokRef;

        const SourceView& srcView = ast.srcView();
        if (srcView.token(startTokRef).id != TokenId::SymLeftParen)
            return endTokRef;

        const TokenRef closeTokRef = ModuleApi::matchingModuleApiDelimiter(srcView, startTokRef, TokenId::SymLeftParen, TokenId::SymRightParen);
        return closeTokRef.isValid() ? closeTokRef : endTokRef;
    }

    bool functionDeclPrefixHasExplicitReturnType(const SourceFile& file, const AstFunctionDecl& functionDecl, const uint32_t prefixEndOffset)
    {
        const Ast& ast = file.ast();
        if (!ast.hasSourceView() || !functionDecl.nodeParamsRef.isValid())
            return false;

        const TokenRef paramsEndTokRef = moduleApiFunctionParamsEndTokRef(ast, functionDecl);
        if (!paramsEndTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();
        for (uint32_t tokIndex = paramsEndTokRef.get() + 1; tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (srcView.tokenByteStart(token) >= prefixEndOffset)
                break;

            if (token.id == TokenId::SymMinusGreater)
                return true;
        }

        return false;
    }

    bool tryFindFunctionReturnTypeInsertOffset(const SourceFile& file, const AstFunctionDecl& functionDecl, const uint32_t prefixEndOffset, uint32_t& outInsertOffset)
    {
        outInsertOffset = 0;
        const Ast& ast  = file.ast();
        if (!ast.hasSourceView() || !functionDecl.nodeParamsRef.isValid())
            return false;

        const TokenRef paramsEndTokRef = moduleApiFunctionParamsEndTokRef(ast, functionDecl);
        if (!paramsEndTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();

        for (uint32_t tokIndex = paramsEndTokRef.get() + 1; tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (srcView.tokenByteStart(token) >= prefixEndOffset)
                break;

            switch (token.id)
            {
                case TokenId::SymMinusGreater:
                    outInsertOffset = srcView.tokenByteStart(token);
                    return true;

                case TokenId::KwdFail:
                case TokenId::KwdWhere:
                case TokenId::SymEqualGreater:
                case TokenId::SymLeftCurly:
                case TokenId::SymSemiColon:
                    outInsertOffset = srcView.tokenByteStart(token);
                    return true;

                default:
                    break;
            }
        }

        outInsertOffset = srcView.tokenByteEnd(srcView.token(paramsEndTokRef));
        return true;
    }

    bool isModuleApiTypeNameQualifierBoundary(const char c)
    {
        return !std::isalnum(static_cast<unsigned char>(c)) && c != '_' && c != '.';
    }

    Utf8 stripCurrentModuleTypeQualifiers(Utf8 typeName, const std::string_view moduleNamespace)
    {
        if (moduleNamespace.empty())
            return typeName;

        Utf8 prefix;
        prefix += moduleNamespace;
        prefix += ".";

        size_t pos = typeName.find(prefix.view());
        while (pos != std::string_view::npos)
        {
            if (pos == 0 || isModuleApiTypeNameQualifierBoundary(typeName[pos - 1]))
            {
                typeName.erase(pos, prefix.size());
                pos = typeName.find(prefix.view(), pos);
                continue;
            }

            pos = typeName.find(prefix.view(), pos + prefix.size());
        }

        return typeName;
    }

    Utf8 buildGeneratedModuleApiTypeName(TaskContext& ctx, const TypeRef typeRef)
    {
        const Utf8 moduleNamespace = buildModuleNamespaceName(ctx.compiler());
        Utf8       typeName        = ctx.typeMgr().get(typeRef).toFullName(ctx);
        return stripCurrentModuleTypeQualifiers(std::move(typeName), moduleNamespace.view());
    }

    bool tryBuildFunctionDeclPrefix(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction || !root.file || !symbolFunction->decl())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, *root.file, root.nodeRef, startOffset, endOffset))
            return false;

        if (symbolFunction->decl()->isNot(AstNodeId::FunctionDecl))
            return false;

        uint32_t bodyStartOffset = 0;
        if (tryFindFunctionBodyStartOffset(root, bodyStartOffset))
            endOffset = bodyStartOffset;

        const SourceView&      srcView = moduleApiNodeSourceView(ctx, root.file->ast(), root.nodeRef);
        const std::string_view source  = srcView.stringView();
        endOffset                      = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;

        if (startOffset >= endOffset)
            return false;

        auto        rawPrefix    = Utf8(source.substr(startOffset, endOffset - startOffset));
        const auto* functionDecl = symbolFunction->decl()->safeCast<AstFunctionDecl>();
        if (functionDecl &&
            symbolFunction->returnTypeRef().isValid() &&
            symbolFunction->returnTypeRef() != ctx.typeMgr().typeVoid() &&
            !functionDeclPrefixHasExplicitReturnType(*root.file, *functionDecl, endOffset))
        {
            uint32_t insertOffset = 0;
            if (tryFindFunctionReturnTypeInsertOffset(*root.file, *functionDecl, endOffset, insertOffset) &&
                insertOffset >= startOffset &&
                insertOffset <= endOffset)
            {
                const Utf8 returnTypeName = buildGeneratedModuleApiTypeName(ctx, symbolFunction->returnTypeRef());
                const Utf8 insertion      = std::format("->{} ", returnTypeName.c_str());
                rawPrefix.insert(insertOffset - startOffset, insertion);
            }
        }

        outPrefix = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, rawPrefix.view(), eol);
        return !outPrefix.empty();
    }

    // An entry of a generated module API states only what an importer cannot recompute.
    // The module is the one the API file describes, the calling convention is Swag, and
    // the flattened symbol name is the scoped declaration name; each of those is the
    // default an importer applies on its own. Only an overload carries a name, because
    // its disambiguating suffix depends on the whole overload set.
    Utf8 buildModuleApiForeignAttribute(TaskContext& ctx, const SymbolFunction& symbolFunction)
    {
        SWC_ASSERT(symbolFunction.callConvKind() == CallConvKind::Swag);

        const Utf8 apiName = symbolFunction.computePublicApiSymbolName(ctx);
        if (apiName == symbolFunction.computePublicApiBaseSymbolName(ctx))
            return "Foreign";

        return Utf8{std::format("Foreign(function: \"{}\")", apiName.c_str())};
    }

    Utf8 buildFunctionSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr;
        if (!symbolFunction)
            return {};

        Utf8 prefix;
        if (!tryBuildFunctionDeclPrefix(ctx, root, eol, prefix))
            return {};

        // A source annotation can understate what the body actually does. Once the body
        // disappears, only its completed, merged summary may become the importer's contract.
        static constexpr std::string_view BODY_ATTRIBUTES[] = {"Inline", "NoInline", "Safety", "Sanity", "Optimize", "Warning", "BorrowSummary"};
        removeModuleApiAttributes(ctx, prefix, BODY_ATTRIBUTES);
        trimTrailingModuleApiDeclarationSeparator(prefix);
        if (prefix.empty())
            return {};

        SmallVector<Utf8> attributes;
        if (!symbolFunction->isForeign())
            attributes.push_back(buildModuleApiForeignAttribute(ctx, *symbolFunction));
        collectMissingFunctionAttributes(attributes, *symbolFunction, false, prefix);

        Utf8 result = buildAttributeListLine(attributes.span(), eol);
        result += prefix;
        return result;
    }

    // Emit a bare `impl Interface for Struct {}` for an empty interface impl that has no
    // member functions to reconstruct it from. The impl prefix (up to the opening brace) is
    // taken verbatim from the source; an empty body is appended.
    bool tryBuildEmptyInterfaceImplSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outSnippet)
    {
        if (!root.file || !root.symbol)
            return false;

        const auto* symImpl = root.symbol->safeCast<SymbolImpl>();
        if (!symImpl || !symImpl->isForInterface())
            return false;

        AstNodeRef implRef;
        if (!tryFindReachableNodeRef(root.file->ast(), symImpl->decl(), implRef))
            return false;

        Utf8 implPrefix;
        if (!tryBuildImplPrefix(ctx, *root.file, implRef, eol, implPrefix))
            return false;

        outSnippet = std::move(implPrefix);
        outSnippet += eol;
        outSnippet += "{";
        outSnippet += eol;
        outSnippet += "}";
        return true;
    }

    const SymbolImpl* semanticImplContext(const Symbol* symbol)
    {
        if (!symbol)
            return nullptr;

        if (const auto* symbolFunction = symbol->safeCast<SymbolFunction>())
            return symbolFunction->declImplContext();

        const SymbolMap* ownerSymMap = symbol->ownerSymMap();
        if (ownerSymMap && ownerSymMap->isImpl())
            return &ownerSymMap->cast<SymbolImpl>();

        return nullptr;
    }

    uint32_t moduleApiRootSortByte(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef)
    {
        constexpr uint32_t moduleApiInvalidByte = 0xFFFFFFFFu;
        uint32_t           startOffset          = moduleApiInvalidByte;
        if (!tryGetModuleApiSnippetStartOffset(ctx, file, nodeRef, startOffset))
            return moduleApiInvalidByte;

        return startOffset;
    }

    struct ModuleApiRootSortProjection
    {
        TaskContext*      ctx  = nullptr;
        const SourceFile* file = nullptr;

        uint32_t operator()(const ModuleApiPublicEntry& entry) const
        {
            SWC_ASSERT(ctx != nullptr);
            SWC_ASSERT(file != nullptr);
            return moduleApiRootSortByte(*ctx, *file, entry.rootRef);
        }
    };

    bool sameGeneratedRoot(const ModuleApiGeneratedRoot& root, const SourceFile& file, const AstNodeRef nodeRef, std::span<const IdentifierRef> namespacePath)
    {
        return root.file == &file &&
               root.nodeRef == nodeRef &&
               sameNamespacePath(root.namespacePath, namespacePath);
    }

    void appendGeneratedGenericRootMethodRoots(TaskContext& ctx, const SymbolStruct& symbolStruct, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (!symbolStruct.isGenericRoot() || symbolStruct.isGenericInstance())
            return;

        for (const SymbolFunction* method : symbolStruct.declaredMethods())
        {
            if (!method || !isGeneratedModuleApiSourceFunction(ctx, *method))
                continue;

            const SourceFile* sourceFile = ctx.compiler().sourceViewFile(*method);
            const SourceFile* astFile    = ctx.compiler().ownerSourceFile(method->srcViewRef());
            if (!astFile)
                astFile = sourceFile;
            if (!sourceFile || !astFile)
                continue;

            AstNodeRef declRef;
            if (!tryFindReachableNodeRef(astFile->ast(), method->decl(), declRef))
                continue;

            ModuleApiGeneratedRoot methodRoot;
            methodRoot.file    = astFile;
            methodRoot.nodeRef = findExportDeclRoot(*astFile, declRef);
            methodRoot.symbol  = method;
            if (methodRoot.nodeRef.isInvalid())
                continue;
            if (!extractPublicNamespacePath(ctx, *astFile, declRef, *method, methodRoot.namespacePath))
                continue;

            appendGeneratedRootUnique(outRoots, std::move(methodRoot));
        }
    }

    Result buildSanitizedRootSnippet(TaskContext& ctx, Utf8& outSnippet, const ModuleApiGeneratedRoot& root, const std::string_view eol)
    {
        outSnippet.clear();
        std::string_view snippetText;
        if (!root.file || !tryGetModuleApiSnippet(ctx, *root.file, root.nodeRef, snippetText))
            return Result::Continue;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, *root.file, root.nodeRef, startOffset, endOffset))
            return Result::Continue;

        outSnippet = buildSanitizedModuleApiSnippet(ctx, *root.file, root.nodeRef, startOffset, snippetText, eol);
        if (const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr)
            prependMissingFunctionAttributes(*symbolFunction, eol, true, outSnippet);
        return Result::Continue;
    }
}

namespace ModuleApiExport
{
    Result validateWholeFileFunctionBodies(TaskContext& ctx, const SourceFile& file)
    {
        Result result = Result::Continue;
        Ast::visit(file.ast(), file.ast().root(), [&](const AstNodeRef nodeRef, const AstNode& node) {
            const auto* declaration = node.safeCast<AstFunctionDecl>();
            if (!declaration || declaration->nodeBodyRef.isInvalid())
                return Ast::VisitResult::Continue;

            // This check needs only bound symbols, never inferred types or constant values.
            const NodePayload::ResolvedSymbols resolved = file.nodePayloadContext().resolveSymbols(nodeRef);
            const auto*                        function = !resolved.symbols.empty() && resolved.symbols.front() ? resolved.symbols.front()->safeCast<SymbolFunction>() : nullptr;
            if (!function)
                return Ast::VisitResult::Continue;

            result = validateExportedFunctionBody(ctx, file, *function, DiagnosticId::cmd_err_api_whole_file_body_not_exportable);
            return result == Result::Continue ? Ast::VisitResult::Continue : Ast::VisitResult::Stop;
        });
        return result;
    }

    bool tryBuildImplPrefix(TaskContext& ctx, const SourceFile& file, const AstNodeRef implRef, const std::string_view eol, Utf8& outPrefix)
    {
        outPrefix.clear();
        if (!implRef.isValid())
            return false;

        const Ast& ast = file.ast();
        if (!ast.hasSourceView())
            return false;

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, file, implRef, startOffset, endOffset))
            return false;

        const AstNode&    implNode    = ast.node(implRef);
        const TokenRef    startTokRef = moduleApiSnippetStartTokRef(ast, implNode);
        const TokenRef    endTokRef   = implNode.tokRefEnd(ast);
        const SourceView& srcView     = moduleApiNodeSourceView(ctx, ast, implRef);

        for (uint32_t tokIndex = startTokRef.get(); tokIndex <= endTokRef.get() && tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token = srcView.token(TokenRef(tokIndex));
            if (token.id != TokenId::SymLeftCurly)
                continue;

            endOffset = srcView.tokenByteStart(token);
            break;
        }

        const std::string_view source = srcView.stringView();
        endOffset                     = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;
        if (startOffset >= endOffset)
            return false;

        outPrefix = buildSanitizedModuleApiSnippet(ctx, file, implRef, startOffset, source.substr(startOffset, endOffset - startOffset), eol);
        trimTrailingModuleApiWhitespace(outPrefix);
        return !outPrefix.empty();
    }

    Result buildGeneratedRootSnippet(TaskContext& ctx, const ModuleApiGeneratedRoot& root, const std::string_view eol, Utf8& outSnippet, ModuleApiValidationStack& validationStack)
    {
        outSnippet.clear();
        if (!root.file)
            return Result::Continue;

        if (root.symbol && root.symbol->isImpl())
        {
            tryBuildEmptyInterfaceImplSnippet(ctx, root, eol, outSnippet);
            return Result::Continue;
        }

        if (const auto* symbolFunction = root.symbol ? root.symbol->safeCast<SymbolFunction>() : nullptr)
        {
            SWC_RESULT(validatePublicFunctionSymbol(ctx, *symbolFunction, validationStack));

            if (symbolFunction->supportsPublicApiForeignExport() && symbolFunction->attributes().hasRtFlag(RtAttributeFlagsE::Inline))
            {
                SWC_RESULT(validateExportedFunctionBody(ctx, *root.file, *symbolFunction, DiagnosticId::cmd_err_api_inline_body_not_exportable));
                return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);
            }

            if (symbolFunction->supportsPublicApiForeignExport() && supportsGeneratedModuleApiForeignFunctions(ctx.compiler()))
            {
                outSnippet = buildFunctionSnippet(ctx, root, eol);
                return Result::Continue;
            }

            // Implicit operations travel as source even without Inline. Their
            // callers need every referenced declaration just as an inline body does.
            if (symbolFunction->attributes().hasRtFlag(RtAttributeFlagsE::Implicit) &&
                !symbolFunction->isGenericRoot() && !symbolFunction->isGenericInstance() &&
                !symbolFunction->hasUnmaterializedGenericBody())
            {
                SWC_RESULT(validateExportedFunctionBody(ctx, *root.file, *symbolFunction, DiagnosticId::cmd_err_api_implicit_body_not_exportable));
            }

            return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);
        }

        if (root.symbol && (root.symbol->isAlias() || root.symbol->isStruct() || root.symbol->isEnum() || root.symbol->isInterface()))
        {
            SWC_RESULT(validatePublicTypeSymbol(ctx, *root.symbol, validationStack));
        }

        if (root.symbol && root.symbol->isStruct() && isModuleApiOpaqueType(*root.symbol))
        {
            if (const auto* symbolStruct = root.symbol->safeCast<SymbolStruct>(); symbolStruct && symbolStruct->isGenericRoot() && !symbolStruct->isGenericInstance())
                return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);

            if (const auto* symbolStruct = root.symbol->safeCast<SymbolStruct>(); symbolStruct && hasGeneratedModuleApiSourceMethod(ctx, *symbolStruct))
                return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);

            return buildOpaqueTypeSnippet(ctx, outSnippet, root, eol);
        }

        return buildSanitizedRootSnippet(ctx, outSnippet, root, eol);
    }

    bool tryFindSemanticImplRef(TaskContext& ctx, const ModuleApiGeneratedRoot& root, AstNodeRef& outImplRef, const SourceFile*& outImplFile)
    {
        outImplRef  = AstNodeRef::invalid();
        outImplFile = nullptr;

        const SymbolImpl* symImpl = semanticImplContext(root.symbol);
        if (!symImpl || !symImpl->decl())
            return false;

        const SourceFile* implFile = ctx.compiler().ownerSourceFile(symImpl->srcViewRef());
        if (!implFile)
            implFile = ctx.compiler().sourceViewFile(*symImpl);
        if (!implFile)
            return false;

        AstNodeRef implRef;
        if (!tryFindReachableNodeRef(implFile->ast(), symImpl->decl(), implRef))
            return false;

        outImplRef  = implRef;
        outImplFile = implFile;
        return true;
    }

    void appendGeneratedRootUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, ModuleApiGeneratedRoot&& root)
    {
        if (!root.file || root.nodeRef.isInvalid())
            return;

        for (const ModuleApiGeneratedRoot& existing : outRoots)
        {
            if (sameGeneratedRoot(existing, *root.file, root.nodeRef, root.namespacePath))
                return;
        }

        outRoots.push_back(std::move(root));
    }

    void mergeGeneratedRootsUnique(std::vector<ModuleApiGeneratedRoot>& outRoots, std::vector<std::vector<ModuleApiGeneratedRoot>>& perFileRoots)
    {
        // The same filter and first-occurrence order as appendGeneratedRootUnique, but a module
        // carries thousands of roots: compare each one only with those sharing its hash.
        std::unordered_map<uint32_t, SmallVector<uint32_t>> rootsByHash;
        for (std::vector<ModuleApiGeneratedRoot>& fileRoots : perFileRoots)
        {
            for (ModuleApiGeneratedRoot& root : fileRoots)
            {
                if (!root.file || root.nodeRef.isInvalid())
                    continue;

                uint32_t hash = Math::hashCombine(Math::hash(root.nodeRef.get()), reinterpret_cast<uint64_t>(root.file));
                for (const IdentifierRef idRef : root.namespacePath)
                    hash = Math::hashCombine(hash, idRef.get());

                SmallVector<uint32_t>& bucket    = rootsByHash[hash];
                bool                   duplicate = false;
                for (const uint32_t index : bucket)
                {
                    if (sameGeneratedRoot(outRoots[index], *root.file, root.nodeRef, root.namespacePath))
                    {
                        duplicate = true;
                        break;
                    }
                }

                if (duplicate)
                    continue;

                bucket.push_back(static_cast<uint32_t>(outRoots.size()));
                outRoots.push_back(std::move(root));
            }
        }
    }

    void appendGeneratedRootsForFile(TaskContext& ctx, const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (fileEntry.publicEntries.empty())
            return;

        const SourceFile* astFile = ctx.compiler().ownerSourceFile(file.ast().srcView().ref());
        if (!astFile)
            astFile = &file;

        std::vector<ModuleApiPublicEntry> sortedEntries = fileEntry.publicEntries;
        std::ranges::stable_sort(sortedEntries, {}, ModuleApiRootSortProjection{.ctx = &ctx, .file = astFile});

        for (const ModuleApiPublicEntry& publicEntry : sortedEntries)
        {
            appendGeneratedRootUnique(outRoots, {.file = astFile, .nodeRef = publicEntry.rootRef, .symbol = publicEntry.symbol, .namespacePath = publicEntry.namespacePath});
            if (const auto* symbolStruct = publicEntry.symbol ? publicEntry.symbol->safeCast<SymbolStruct>() : nullptr)
                appendGeneratedGenericRootMethodRoots(ctx, *symbolStruct, outRoots);
        }
    }
}

SWC_END_NAMESPACE();

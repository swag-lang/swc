#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class MicroBuilder;
class CompilerInstance;
class ConstantManager;
class TypeManager;
class TypeGen;
class IdentifierManager;
class SourceView;
class SymbolVariable;
struct ResolvedCallArgument;
struct Token;

struct CodeGenNodePayload
{
    enum class StorageKind : uint8_t
    {
        Value,
        Address,
    };

    MicroReg    reg         = MicroReg::invalid();
    TypeRef     typeRef     = TypeRef::invalid();
    StorageKind storageKind = StorageKind::Value;
};

class CodeGen
{
public:
    explicit CodeGen(Sema& sema);
    Result exec(SymbolFunction& symbolFunc, AstNodeRef root);

    Sema&                     sema() { return *SWC_CHECK_NOT_NULL(sema_); }
    const Sema&               sema() const { return *SWC_CHECK_NOT_NULL(sema_); }
    TaskContext&              ctx();
    const TaskContext&        ctx() const;
    CompilerInstance&         compiler();
    const CompilerInstance&   compiler() const;
    ConstantManager&          cstMgr();
    const ConstantManager&    cstMgr() const;
    TypeManager&              typeMgr();
    const TypeManager&        typeMgr() const;
    TypeGen&                  typeGen();
    const TypeGen&            typeGen() const;
    IdentifierManager&        idMgr();
    const IdentifierManager&  idMgr() const;
    Ast&                      ast();
    const Ast&                ast() const;
    SourceView&               srcView(SourceViewRef srcViewRef);
    const SourceView&         srcView(SourceViewRef srcViewRef) const;
    AstNode&                  node(AstNodeRef nodeRef) { return ast().node(nodeRef); }
    const AstNode&            node(AstNodeRef nodeRef) const { return ast().node(nodeRef); }
    AstVisit&                 visit() { return visit_; }
    const AstVisit&           visit() const { return visit_; }
    AstNodeRef                curNodeRef() const { return visit_.currentNodeRef(); }
    const Token&              token(const SourceCodeRef& codeRef) const;
    void                      appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const;
    SymbolFunction&           function() { return *SWC_CHECK_NOT_NULL(function_); }
    const SymbolFunction&     function() const { return *SWC_CHECK_NOT_NULL(function_); }
    CodeGenNodePayload*       payload(AstNodeRef nodeRef) const;
    void                      setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload);
    const CodeGenNodePayload* variablePayload(const SymbolVariable& sym) const;
    CodeGenNodePayload&       inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayload(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayloadValue(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    CodeGenNodePayload&       setPayloadAddress(AstNodeRef nodeRef, TypeRef typeRef = TypeRef::invalid());
    static void               setPayloadValue(CodeGenNodePayload& payload);
    static void               setPayloadAddress(CodeGenNodePayload& payload);
    MicroReg                  nextVirtualRegisterForType(TypeRef typeRef);
    bool                      canUseOperandRegDirect(const CodeGenNodePayload& operandPayload) const;
    MicroReg                  nextVirtualRegister() { return MicroReg::virtualReg(nextVirtualRegister_++); }
    MicroReg                  nextVirtualIntRegister() { return MicroReg::virtualIntReg(nextVirtualRegister_++); }
    MicroReg                  nextVirtualFloatRegister() { return MicroReg::virtualFloatReg(nextVirtualRegister_++); }
    MicroBuilder&             builder() { return *SWC_CHECK_NOT_NULL(builder_); }
    const MicroBuilder&       builder() const { return *SWC_CHECK_NOT_NULL(builder_); }

private:
    void   setVisitors();
    Result emitConstant(AstNodeRef nodeRef);
    Result preNode(AstNode& node);
    Result postNode(AstNode& node);
    Result preNodeChild(AstNode& node, AstNodeRef& childRef);
    Result postNodeChild(AstNode& node, AstNodeRef& childRef);

    Sema*                                                         sema_ = nullptr;
    AstVisit                                                      visit_;
    SymbolFunction*                                               function_            = nullptr;
    MicroBuilder*                                                 builder_             = nullptr;
    uint32_t                                                      nextVirtualRegister_ = 1;
    std::unordered_map<const SymbolVariable*, CodeGenNodePayload> variablePayloads_;
};

SWC_END_NAMESPACE();

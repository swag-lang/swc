#pragma once
#include "Sema/Symbol/DeclContext.h"

SWC_BEGIN_NAMESPACE()

class ModuleDecl : public DeclContext
{
public:
    ModuleDecl() :
        DeclContext(DeclKind::Module)
    {
    }
};

class NamespaceDecl : public DeclContext
{
public:
    NamespaceDecl() :
        DeclContext(DeclKind::Namespace)
    {
    }
};

SWC_END_NAMESPACE()

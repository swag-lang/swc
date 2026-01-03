#global internal

alias SSW = Swag

alias DWORD1 = u32
const A: DWORD1 = 0
#assert(#typeof(A) == u32)
#assert(#typeof(DWORD1) == u32)

#[Swag.Strict]
alias DWORD2 = u32
//const BasedOnDWORD2: DWORD2 = 0

#[Swag.Strict]
alias SSW1 = Swag // swc-expected-error {{sema_err_not_type}}

alias SRWLOCK = *void
//const SRWLOCK_INIT: *void = null

/*
namespace TOTO
{
    alias HANDLE  = *void
    alias DWORD   = u32
    alias SRWLOCK = *void
    alias USHORT  = u16
    alias ULONG   = u32
    alias ULONG64 = u64
    alias CHAR    = u8
    alias WCHAR   = u16
    alias BOOL    = u8

    const STD_OUTPUT_HANDLE    = cast #bit (u32) -11
    const MB_CANCELTRYCONTINUE = 0x00000006
    const MB_ICONERROR         = 0x00000010
    const IDCANCEL             = 2
    const IDTRYAGAIN           = 10
    const IDCONTINUE           = 11
    const FALSE:               BOOL = 0
    const TRUE:                BOOL = 1
    const SRWLOCK_INIT         = cast(SRWLOCK) null

    struct SYMBOL_INFO
    {
        SizeOfStruct:     ULONG
        TypeIndex:        ULONG           // Type Index of symbol
        Reserved:         [2] ULONG64
        Index:            ULONG
        Size:             ULONG
        ModBase:          ULONG64         // Base Address of module comtaining this symbol
        Flags:            ULONG
        Value:            ULONG64         // Value of symbol, ValuePresent should be 1
        Address:          ULONG64         // Address of symbol including base address of module
        Register:         ULONG           // register holding value or pointer to value
        Scope:            ULONG           // scope of the symbol
        Tag:              ULONG           // pdb classification
        NameLen:          ULONG           // Actual length of name
        MaxNameLen:       ULONG
        Name:             [1] CHAR        // Name of symbol
    }

    struct SYMBOL_INFOW
    {
        SizeOfStruct:     ULONG
        TypeIndex:        ULONG           // Type Index of symbol
        Reserved:         [2] ULONG64
        Index:            ULONG
        Size:             ULONG
        ModBase:          ULONG64         // Base Address of module comtaining this symbol
        Flags:            ULONG
        Value:            ULONG64         // Value of symbol, ValuePresent should be 1
        Address:          ULONG64         // Address of symbol including base address of module
        Register:         ULONG           // register holding value or pointer to value
        Scope:            ULONG           // scope of the symbol
        Tag:              ULONG           // pdb classification
        NameLen:          ULONG           // Actual length of name
        MaxNameLen:       ULONG
        Name:             [1] WCHAR       // Name of symbol
    }

    struct IMAGEHLP_LINE64
    {
        SizeOfStruct:     DWORD        // set to sizeof(IMAGEHLP_LINE64)
        Key:              *void        // internal
        LineNumber:       DWORD        // line number in file
        FileName:         [*] CHAR     // full filename
        Address:          ULONG64      // first instruction of line
    }

    struct IMAGEHLP_LINEW64
    {
        SizeOfStruct:     DWORD         // set to sizeof(IMAGEHLP_LINEW64)
        Key:              *void         // internal
        LineNumber:       DWORD         // line number in file
        FileName:         [*] WCHAR     // full filename
        Address:          ULONG64       // first instruction of line
    }
}*/
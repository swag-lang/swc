#global export

alias SFGAOF = ULONG

#[Swag.Pack(1)]
struct SHITEMID
{
    public
    {
        cb:   USHORT
        abID: [1] BYTE
    }
}

#[Swag.Pack(1)]
struct ITEMIDLIST
{
    public mkid: SHITEMID
}

alias PIDLIST_ABSOLUTE  = *ITEMIDLIST?
alias PCIDLIST_ABSOLUTE = const *ITEMIDLIST?

// Opaque COM interface views used only as borrowed arguments of Shell operations.
#[Swag.Opaque]
struct IBindCtx { public lpVtbl: const *void }
#[Swag.Opaque]
struct IShellItemArray { public lpVtbl: *IUnknownVtbl }

// Shell file-operation interface. Unused slots preserve their ABI positions.
struct IFileOperation
{
    public lpVtbl: *IFileOperationVtbl
}

struct IFileOperationVtbl
{
    public
    {
        base:                    IUnknownVtbl
        Advise:                  *void?
        Unadvise:                *void?
        SetOperationFlags:       func(*IFileOperation, DWORD)->HRESULT
        SetProgressMessage:      *void?
        SetProgressDialog:       *void?
        SetProperties:           *void?
        SetOwnerWindow:          *void?
        ApplyPropertiesToItem:   *void?
        ApplyPropertiesToItems:  *void?
        RenameItem:              *void?
        RenameItems:             func(*IFileOperation, *IUnknown, LPCWSTR)->HRESULT
        MoveItem:                *void?
        MoveItems:               *void?
        CopyItem:                *void?
        CopyItems:               *void?
        DeleteItem:              *void?
        DeleteItems:             *void?
        NewItem:                 *void?
        PerformOperations:       func(*IFileOperation)->HRESULT
        GetAnyOperationsAborted: func(*IFileOperation, *BOOL)->HRESULT
    }
}

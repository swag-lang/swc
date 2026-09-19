#global export

#foreignlib("comctl32")

alias SUBCLASSPROC = func(HWND, UINT, WPARAM, LPARAM, UINT_PTR, DWORD_PTR)->LRESULT

#[Swag.Foreign("comctl32", callconv: Swag.CallConv.C)]
{
    func SetWindowSubclass(hWnd: HWND, pfnSubclass: SUBCLASSPROC, uIdSubclass: UINT_PTR, dwRefData: DWORD_PTR)->BOOL
    func RemoveWindowSubclass(hWnd: HWND, pfnSubclass: SUBCLASSPROC, uIdSubclass: UINT_PTR)->BOOL
    func DefSubclassProc(hWnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM)->LRESULT
}

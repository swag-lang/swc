#global fileprivate // swc-option sema-only
#global skip
//#global skip
func ReleaseDC()->s32 => 0

func createContext(hWnd: *void)
{
    defer discard ReleaseDC()
}

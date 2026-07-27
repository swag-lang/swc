#global private

// '#fail' and '#nofail' select opposite exit paths of the enclosing scope.
func deferBothPaths()
{
    defer #fail #nofail @print("x")     // swc-expected-error {{sema_err_defer_fail_conflict}}
}

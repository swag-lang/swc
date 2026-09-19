#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let event = expect CreateEventW(null, TRUE, TRUE, null)
    defer CloseHandle(event)
    let ready = expect MsgWaitForMultipleObjectsEx(1, &event, 0, QS_ALLINPUT, MWMO_INPUTAVAILABLE)
    Swag.assert(ready == WAIT_OBJECT_0)
    expect ResetEvent(event)
    let timeout = expect MsgWaitForMultipleObjectsEx(1, &event, 0, 0, 0)
    Swag.assert(timeout == WAIT_TIMEOUT)
    let empty = expect MsgWaitForMultipleObjectsEx(0, null, 0, 0, 0)
    Swag.assert(empty == WAIT_TIMEOUT)

    let invalid = INVALID_HANDLE_VALUE
    discard catch MsgWaitForMultipleObjectsEx(1, &invalid, 0, 0, 0) as error
    Swag.assert((error is SystemError))
}

#test
{
    var animations: BOOL
    expect SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0)
    Swag.assert(animations == TRUE or animations == FALSE)
    catch SystemParametersInfoW(U32.Max, 0, null, 0) as error
    Swag.assert((error is SystemError))
    Swag.assert(#sizeof(DWM_BLURBEHIND) == 24)
    Swag.assert(#offsetof(DWM_BLURBEHIND.hRgnBlur) == 8)
    Swag.assert(#sizeof(LASTINPUTINFO) == 8)
}

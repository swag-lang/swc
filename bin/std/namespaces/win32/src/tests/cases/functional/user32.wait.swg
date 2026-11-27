#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

#test
{
    let timer = CreateWaitableTimerExW(null, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, SYNCHRONIZE | TIMER_MODIFY_STATE)
    Swag.require(timer != null)
    defer CloseHandle(timer)
    let dueTime: LARGE_INTEGER = -10000
    let armed = SetWaitableTimer(timer, &dueTime, 0, null, null, FALSE)
    Swag.require(armed != 0)
    let ready = expect MsgWaitForMultipleObjectsEx(1, &timer, 1000, 0, 0)
    Swag.require(ready == WAIT_OBJECT_0)
}

#test
{
    let event = expect CreateEventW(null, TRUE, TRUE, null)
    defer CloseHandle(event)
    let ready = expect MsgWaitForMultipleObjectsEx(1, &event, 0, QS_ALLINPUT, MWMO_INPUTAVAILABLE)
    Swag.require(ready == WAIT_OBJECT_0)
    expect ResetEvent(event)
    let timeout = expect MsgWaitForMultipleObjectsEx(1, &event, 0, 0, 0)
    Swag.require(timeout == WAIT_TIMEOUT)
    let empty = expect MsgWaitForMultipleObjectsEx(0, null, 0, 0, 0)
    Swag.require(empty == WAIT_TIMEOUT)

    let invalid = INVALID_HANDLE_VALUE
    var errorOutcome: Swag.Error
    discard catch MsgWaitForMultipleObjectsEx(1, &invalid, 0, 0, 0) as errorOutcome
    let error = errorOutcome.value()
    Swag.require((error is SystemError))
}

#test
{
    var animations: BOOL
    expect SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0)
    Swag.require(animations == TRUE or animations == FALSE)
    var errorOutcome: Swag.Error
    catch SystemParametersInfoW(U32.Max, 0, null, 0) as errorOutcome
    let error = errorOutcome.value()
    Swag.require((error is SystemError))
    Swag.require(#sizeof(DWM_BLURBEHIND) == 24)
    Swag.require(#offsetof(DWM_BLURBEHIND.hRgnBlur) == 8)
    Swag.require(#sizeof(LASTINPUTINFO) == 8)
}

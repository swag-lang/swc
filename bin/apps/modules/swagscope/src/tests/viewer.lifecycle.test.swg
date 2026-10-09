#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func lifecycleTestLoad(fileName: string)->s32 fail
{
    if fileName == "success" do
        return 42
    fail Errors.InvalidFormatError{Errors.mkString(fileName)}
}

// The worker's caught value has ended before finish reads its independently owned message.
#test
{
    var load: Viewer.BackgroundLoad's32
    load.start("worker-owned failure", &lifecycleTestLoad)
    load.task.wait()
    var value: s32
    let failure = load.finish(&value)
    Swag.assert(failure == failureShape(appStrings().ui_FailureFormat, "worker-owned failure"))
    Swag.assert(not load.started)

    load.start("success", &lifecycleTestLoad)
    load.task.wait()
    let success = load.finish(&value)
    Swag.assert(success.isEmpty() and value == 42)

    load.start("replacement failure", &lifecycleTestLoad)
    load.task.wait()
    let replacement = load.finish(&value)
    Swag.assert(replacement == failureShape(appStrings().ui_FailureFormat, "replacement failure"))
    Swag.assert(failure == failureShape(appStrings().ui_FailureFormat, "worker-owned failure"))
}

#global private

struct(T) MetadataSignal
{
    callbacks: [..] T?
}

impl MetadataSignal
{
    mtd call(params: ...)
    {
        for callback in .callbacks
        {
            #ast
            {
                let signature = #typeof(T)
                return #stringof("callback(cast(", signature.parameters[0].pointedType.fullname, ") params[0])")
            }
        }
    }
}

interface IMetadataReceiver
{
    mtd notify()
}

struct MetadataReceiver
{
    signal: MetadataSignal'func||(*MetadataReceiver)
    count: s32
}

// Reflection reaches this completed method while emit is still instantiating the
// signal's #ast. Its runtime call graph must not become a compile-time dependency.
impl IMetadataReceiver for MetadataReceiver
{
    mtd impl notify()
    {
        .emit()
    }
}

impl MetadataReceiver
{
    mtd emit()
    {
        .signal.call(me)
        .count += 1
    }
}

// Ready optional metadata pointers must still become callable during #run.
#[Swag.ExportType(.Methods)]
struct MetadataReady
{
    value: s32
}

impl MetadataReady
{
    mtd read()->s32
    {
        return .value
    }
}

func metadataCallGraphWorks()
{
    var receiver: MetadataReceiver
    receiver.emit()
    let callback: IMetadataReceiver = &receiver
    callback.notify()
    Swag.assert(receiver.count == 2)

    var ready = MetadataReady{value: 42}
    let info = cast(const *Swag.TypeInfoStruct) #typeof(MetadataReady)
    Swag.assert(info.methods.count == 1)
    let address = info.methods![0].value
    Swag.assert(address != null)
    let read = cast(func(*MetadataReady)->s32) address
    Swag.assert(read(&ready) == 42)
}

#run
{
    metadataCallGraphWorks()
}

#test
{
    metadataCallGraphWorks()
}

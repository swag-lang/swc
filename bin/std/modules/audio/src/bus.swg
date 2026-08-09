using Core, Core.Errors

// Groups voices in a controllable submix.
//
// Route one or more [[Audio.Voice]] instances through a bus with
// [[Audio.Voice.setRouting]]. Volume changes apply to every routed voice. Buses
// may target a parent bus to form a mixing graph.
public struct Bus
{
    readonly
    {
        channelCount: u32            // Number of channels mixed by this bus.
        parent:       #null *Bus     // Parent bus, or `null` for the mastering output.
    }

    internal
    {
        allocationAllocator: IAllocator = undefined     // Allocator that owns this bus.
        handle:              #null *void                // Backend-owned submix handle.
    }
}

public impl Bus
{
    // Creates a bus with the requested channel count.
    //
    // When `parent` is non-null, this bus sends its output to that bus;
    // otherwise it sends to the mastering output. The caller owns the returned
    // allocation and must eventually call [[Audio.Bus.destroy]]. The parent
    // must outlive this bus. Success returns a non-null pointer.
    func create(channelCount: u32, parent: #null *Bus = null)->#null *Bus fail
    {
        if !g_Driver.isCreated do
            fail BadParameterError{"audio engine is not created"}
        if channelCount == 0 do
            fail BadParameterError{"bus channel count must be greater than zero"}
        if parent and !parent.handle do
            fail BadParameterError{"parent bus is not valid"}

        let allocator = g_Driver.allocationAllocator
        let bus       = Memory.new'Bus(allocator)
        bus.allocationAllocator = allocator
        defer #fail Memory.delete(bus, allocator)
        createNative(bus, channelCount, parent)
        bus.channelCount = channelCount
        bus.parent       = parent

        Sync.scopedLock(&g_Driver.mutexBuses)
        g_Driver.buses.add(bus)
        return bus
    }

    // Destroys the native submix and frees this bus immediately.
    //
    // Voices and child buses must be rerouted or destroyed first. The pointer
    // is invalid after this method returns.
    mtd destroy()
    {
        .destroyNative()

        Sync.scopedLock(&g_Driver.mutexBuses)
        g_Driver.buses.remove(me)
        let allocator = .allocationAllocator
        Memory.delete(&me, allocator)
    }

    // Sets the bus gain in decibels.
    //
    // `batchId` is forwarded to backends that support deferred operation sets.
    mtd setVolumeDb(decibels: f32, batchId: u32 = 0) fail
    {
        .setVolume(decibelsToLinearGain(decibels), batchId)
    }

    // Returns the current bus gain in decibels.
    mtd volumeDb()->f32 fail
    {
        return linearGainToDecibels(.volume())
    }
}

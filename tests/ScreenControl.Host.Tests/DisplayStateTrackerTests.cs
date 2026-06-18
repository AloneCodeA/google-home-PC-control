using ScreenControl.Host.Display;

namespace ScreenControl.Host.Tests;

public sealed class DisplayStateTrackerTests
{
    [Theory]
    [InlineData(0u, false)]
    [InlineData(1u, true)]
    [InlineData(2u, true)]
    public void Update_MapsWindowsConsoleDisplayState(uint nativeState, bool expectedIsOn)
    {
        var tracker = new DisplayStateTracker();
        bool? observedState = null;
        tracker.DisplayStateChanged += (_, eventArgs) => observedState = eventArgs.IsOn;

        tracker.Update(nativeState);

        Assert.Equal(expectedIsOn, tracker.IsDisplayOn);
        Assert.Equal(expectedIsOn, observedState);
    }

    [Fact]
    public void Update_WithUnchangedState_DoesNotRaiseDuplicateEvent()
    {
        var tracker = new DisplayStateTracker();
        int eventCount = 0;
        tracker.DisplayStateChanged += (_, _) => eventCount++;

        tracker.Update(1);
        tracker.Update(2);

        Assert.Equal(1, eventCount);
    }

    [Fact]
    public void Update_WithUnknownNativeState_RejectsValue()
    {
        var tracker = new DisplayStateTracker();

        Assert.Throws<ArgumentOutOfRangeException>(() => tracker.Update(3));
    }
}

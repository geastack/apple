// The recognizer's state/location are deterministic; hit testing, coordinate
// conversion, label responder methods and event bubbling are production code.
@interface TestPressRecognizer : NSPressGestureRecognizer
@property(nonatomic, assign) NSGestureRecognizerState testState;
@property(nonatomic, assign) NSPoint windowPoint;
@end
@implementation TestPressRecognizer
- (NSGestureRecognizerState)state { return self.testState; }
- (NSPoint)locationInView:(NSView *)view
{
    return [view convertPoint:self.windowPoint fromView:nil];
}
@end

@interface TestMouseView : NSView
@property(nonatomic, assign) int downs;
@property(nonatomic, assign) int moves;
@property(nonatomic, assign) int ups;
@end
@implementation TestMouseView
- (void)mouseDown:(NSEvent *)event { (void)event; ++_downs; }
- (void)mouseDragged:(NSEvent *)event { (void)event; ++_moves; }
- (void)mouseUp:(NSEvent *)event { (void)event; ++_ups; }
@end

static void require(bool condition, const char *message)
{
    if (!condition) { std::fprintf(stderr, "FAIL: %s\n", message); std::exit(1); }
}

static void tag(NSView *view, int node)
{
    objc_setAssociatedObject(view, "gea.node_id", @(node), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        using namespace gea::embedded::ui;
        using namespace gea::framework::events;
        auto &state = treeState();
        auto &tree = Tree::instance();
        // Logical tree: grid -> block -> label. No app-specific handlers or
        // coordinate hit-testing workaround; listeners use normal bubbling.
        state.nodeCount = 3;
        state.nodes[0].parent = -1;
        state.nodes[1].parent = 0;
        state.nodes[2].parent = 1;
        std::vector<PointerEvent> received;
        bool stopAtBlock = false;
        for (int node = 0; node < 3; ++node) {
            for (const char *type : {"pointerdown", "pointermove", "pointerup", "click"}) {
                tree.setEventListener(node, type, [&, node](PointerEvent &event) {
                    received.push_back(event);
                    if (node == 1 && stopAtBlock) event.stopPropagation();
                });
            }
        }

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 600)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSView *outer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 550)];
        [window.contentView addSubview:outer];
        NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(30, 40, 500, 500)];
        [outer addSubview:root];
        tag(root, 0);
        TestMouseView *block = [[TestMouseView alloc] initWithFrame:NSMakeRect(100, 100, 200, 80)];
        [root addSubview:block];
        tag(block, 1);
        GeaLabelTextField *label = [[GeaLabelTextField alloc] initWithFrame:NSMakeRect(10, 30, 100, 20)];
        label.stringValue = @"Block title";
        label.editable = NO;
        label.selectable = NO;
        label.bezeled = NO;
        label.bordered = NO;
        label.drawsBackground = NO;
        [block addSubview:label];
        tag(label, 2);

        GeaRootClickBridge *bridge = [GeaRootClickBridge new];
        bridge.rootView = root;
        TestPressRecognizer *recognizer = [TestPressRecognizer new];
        [root addGestureRecognizer:recognizer];
        auto fire = [&](NSGestureRecognizerState phase, NSPoint point) {
            recognizer.testState = phase;
            recognizer.windowPoint = [root convertPoint:point toView:nil];
            [bridge fire:recognizer];
        };
        auto mouseEvent = [&](NSView *view) {
            const NSPoint point = [view convertPoint:NSMakePoint(5, 5) toView:nil];
            return [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point
                modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
                context:nil eventNumber:1 clickCount:1 pressure:1];
        };

        const std::string test = argc > 1 ? argv[1] : "label";
        if (test == "mouse") {
            [root removeGestureRecognizer:recognizer];
            NSPressGestureRecognizer *press = [[NSPressGestureRecognizer alloc]
                initWithTarget:bridge action:@selector(fire:)];
            press.minimumPressDuration = 0;
            press.allowableMovement = 10000;
            press.delegate = bridge;
            [root addGestureRecognizer:press];
            [NSApp finishLaunching];
            [window orderBack:nil];
            [window makeKeyWindow];
            const NSEventType phases[] = {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseDragged,
                NSEventTypeLeftMouseDragged, NSEventTypeLeftMouseUp};
            const NSPoint points[] = {NSMakePoint(115, 145), NSMakePoint(350, 145),
                NSMakePoint(700, -20), NSMakePoint(700, -20)};
            for (int i = 0; i < 4; ++i) {
                NSPoint point = [root convertPoint:points[i] toView:nil];
                NSEvent *event = [NSEvent mouseEventWithType:phases[i] location:point
                    modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                    context:nil eventNumber:i + 1 clickCount:1 pressure:1];
                [window sendEvent:event];
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            }
            [window orderOut:nil];
            require(received.size() == 12, "AppKit must deliver down, two moves and up to each ancestor, without a click");
            const PointerEventType types[] = {PointerEventType::TouchStart, PointerEventType::TouchMove,
                PointerEventType::TouchMove, PointerEventType::TouchEnd};
            for (int i = 0; i < 12; ++i) {
                const auto &event = received[i];
                require(event.targetId == 2 && event.currentTargetId == 2 - i % 3,
                    "AppKit must retain the label target and bubble through its ancestors");
                require(event.type == types[i / 3], "AppKit must deliver mouse phases in order");
                require(event.clientX == points[i / 3].x && event.clientY == 500 - points[i / 3].y,
                    "AppKit must preserve coordinates when dragging across containers and outside the window");
            }
        } else if (test == "offset") {
            outer.frame = NSMakeRect(80, 60, 550, 550);
            fire(NSGestureRecognizerStateBegan, NSMakePoint(115, 115));
            require(bridge.pressedNodeId == 1, "an offset root must hit the block, not the surrounding grid");
            received.clear();
            fire(NSGestureRecognizerStateEnded, NSMakePoint(115, 115));
            bridge.originX = 200;
            bridge.originY = 30;
            received.clear();
            fire(NSGestureRecognizerStateBegan, NSMakePoint(115, 145));
            require(received.size() == 3 && received[0].targetId == 2,
                "an offset pane must preserve its label target and ancestors");
            require(received[0].clientX == 315 && received[0].clientY == 385,
                "pane origin must be added to tree coordinates");
        } else if (test == "controls") {
            // Both delegate filtering and initial targeting must use the root's
            // coordinate space, including when its parent is offset.
            outer.frame = NSMakeRect(80, 60, 550, 550);
            require([bridge gestureRecognizer:recognizer shouldAttemptToRecognizeWithEvent:mouseEvent(label)],
                "non-editable labels must allow the root recognizer");
            for (NSView *control in @[[NSTextField new], [NSTextView new], [GeaCanvasView new], [NSScroller new],
                [NSButton new], [NSSlider new], [NSSwitch new], [NSStepper new], [NSPopUpButton new]]) {
                control.frame = NSMakeRect(320, 200, 120, 60);
                [root addSubview:control];
                require(![bridge gestureRecognizer:recognizer shouldAttemptToRecognizeWithEvent:mouseEvent(control)],
                    "native controls, canvases and scrollers must retain their own mouse handling");
                [control removeFromSuperview];
            }
            NSEvent *event = mouseEvent(label);
            [label mouseDown:event];
            [label mouseDragged:event];
            [label mouseUp:event];
            require(block.downs == 1 && block.moves == 1 && block.ups == 1,
                "labels must forward mouse phases without entering NSTextField tracking");
        } else {
            fire(NSGestureRecognizerStateBegan, NSMakePoint(115, 145));
            require(bridge.pressedNodeId == 2, "a label press must preserve the label target");
            require(received.size() == 3, "pointerdown must reach label, block and grid once each");
            for (int i = 0; i < 3; ++i) {
                require(received[i].targetId == 2 && received[i].currentTargetId == 2 - i,
                    "bubbling must preserve target while changing currentTarget");
                require(received[i].clientX == 115 && received[i].clientY == 355,
                    "pointerdown must carry top-down root coordinates");
            }
            received.clear();
            // Leave both the block and the window: the press retains its target.
            fire(NSGestureRecognizerStateChanged, NSMakePoint(700, -20));
            require(received.size() == 3 && received[0].targetId == 2,
                "drag must stay on the pressed label and bubble to its block");
            received.clear();
            fire(NSGestureRecognizerStateEnded, NSMakePoint(700, -20));
            require(received.size() == 3 && received[0].type == PointerEventType::TouchEnd,
                "a drag release must bubble once without a click");
            require(bridge.pressedNodeId == -1, "release must clear the pressed target");
            received.clear();
            stopAtBlock = true;
            fire(NSGestureRecognizerStateBegan, NSMakePoint(115, 145));
            require(received.size() == 2, "stopPropagation on the block must prevent grid creation");
            fire(NSGestureRecognizerStateCancelled, NSMakePoint(115, 145));
            require(bridge.pressedNodeId == -1, "cancellation must clear the pressed target");
            stopAtBlock = false;
            received.clear();
            fire(NSGestureRecognizerStateBegan, NSMakePoint(10, 10));
            require(received.size() == 1 && received[0].targetId == 0,
                "empty grid space must still target the grid");
            received.clear();
            fire(NSGestureRecognizerStateEnded, NSMakePoint(10, 10));
            require(received.size() == 2 && received[1].type == PointerEventType::Click,
                "an ordinary click must still fire once");
            label.hidden = YES;
            received.clear();
            fire(NSGestureRecognizerStateBegan, NSMakePoint(115, 145));
            require(received.size() == 2 && received[0].targetId == 1,
                "hidden labels must not intercept the block");
        }
        std::printf("native pointer routing passed: %s\n", test.c_str());
    }
}

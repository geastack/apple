static void require(bool value, const char *message)
{
    if (value) return;
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
}

@interface GeaInputTestField : NSTextField
@end
@implementation GeaInputTestField
+ (Class)cellClass { return [GeaInputCell class]; }
@end

static NSRect inkBounds(NSTextFieldCell *cell, NSView *view, NSString *text, NSTextAlignment alignment)
{
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = alignment;
    cell.attributedStringValue = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName:[NSFont systemFontOfSize:14],
        NSForegroundColorAttributeName:NSColor.blackColor,
        NSParagraphStyleAttributeName:paragraph
    }];
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
        pixelsWide:160 pixelsHigh:40 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:image]];
    [cell drawWithFrame:NSMakeRect(0, 0, 160, 40) inView:view];
    [NSGraphicsContext restoreGraphicsState];
    int minX = 160, minY = 40, maxX = -1, maxY = -1;
    for (int y = 0; y < 40; ++y) for (int x = 0; x < 160; ++x) {
        NSColor *pixel = [image colorAtX:x y:y];
        if (pixel.alphaComponent < 0.1) continue;
        minX = std::min(minX, x); minY = std::min(minY, y);
        maxX = std::max(maxX, x); maxY = std::max(maxY, y);
    }
    require(maxX >= minX && maxY >= minY, "text must paint native pixels");
    return NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

int main()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        GeaLabelTextField *field = [[GeaLabelTextField alloc] initWithFrame:NSMakeRect(0, 0, 160, 40)];
        field.bezeled = NO; field.bordered = NO; field.drawsBackground = NO;
        GeaTextCell *cell = (GeaTextCell *)field.cell;
        cell.contentInsets = NSEdgeInsetsMake(8, 11, 9, 13);
        const NSRect content = [cell contentRectForBounds:field.bounds inView:field];
        require(content.origin.x == 11 && content.size.width == 136 && content.size.height == 23,
            "CSS padding and borders define the content box");
        require(content.origin.y == (field.isFlipped ? 8 : 9), "CSS top inset follows the native coordinate space");
        const NSRect left = inkBounds(cell, field, @"AppKit", NSTextAlignmentLeft);
        const NSRect center = inkBounds(cell, field, @"AppKit", NSTextAlignmentCenter);
        const NSRect right = inkBounds(cell, field, @"AppKit", NSTextAlignmentRight);
        require(NSMinX(left) >= 11 && NSMaxX(right) <= 148, "text must stay inside horizontal padding");
        require(NSMinY(left) >= 8 && NSMaxY(left) <= 32, "text must stay inside vertical padding");
        require(NSMinX(center) > NSMinX(left) + 25 && NSMinX(right) > NSMinX(center) + 25,
            "left, center and right alignment position actual native ink");
        require(std::abs(NSMidX(center) - NSMidX(content)) <= 2, "centered text must use the content box center");
        GeaInputTestField *input = [[GeaInputTestField alloc] initWithFrame:NSMakeRect(0, 0, 160, 40)];
        input.bezeled = NO; input.bordered = NO; input.drawsBackground = NO;
        input.editable = YES; input.selectable = YES; input.usesSingleLineMode = YES;
        input.font = [NSFont systemFontOfSize:14];
        input.stringValue = @"AppKit";
        ((GeaInputCell *)input.cell).contentInsets = NSEdgeInsetsMake(8, 11, 9, 13);
        const NSRect editor = [input.cell titleRectForBounds:input.bounds];
        require(editor.origin.x == 11 && editor.size.width == 136 && editor.size.height == 23,
            "editable text uses the CSS content box for selection and caret tracking");
        const NSRect inputInk = inkBounds((NSTextFieldCell *)input.cell, input, @"AppKit", NSTextAlignmentLeft);
        require(NSMinX(inputInk) >= 11 && NSMinX(inputInk) <= 14 && NSMaxX(inputInk) <= 148,
            "editable native text honors horizontal padding once");
        require(NSMinY(inputInk) >= 7 && NSMaxY(inputInk) <= 33,
            "editable native text honors vertical padding");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window.contentView addSubview:input];
        [window makeKeyAndOrderFront:nil];
        [input selectText:nil];
        NSText *fieldEditor = input.currentEditor;
        require(fieldEditor != nil, "native field editor must attach when focused");
        const NSRect editing = [input convertRect:fieldEditor.bounds fromView:fieldEditor];
        require(editing.origin.x >= 11 && editing.origin.x <= 14 && NSMaxX(editing) <= 148,
            "focused field editor honors the CSS horizontal padding once");
        require(editing.origin.y >= 8 && NSMaxY(editing) <= 32,
            "focused field editor honors the CSS vertical padding");
        [window orderOut:nil];
        std::printf("native text boxes passed: labels, input painting and focused field editor\n");
    }
}

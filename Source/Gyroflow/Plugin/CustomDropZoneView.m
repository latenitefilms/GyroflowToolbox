//
//  CustomButtonView.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 29/01/2023.
//

#import "CustomDropZoneView.h"
#import <FxPlug/FxPlugSDK.h>

static NSString *const kFinalCutProUTI = @"com.apple.flexo.proFFPasteboardUTI";

@interface CustomDropZoneView ()

@property (nonatomic) bool dragIsOver;

@end

@implementation CustomDropZoneView {
    NSButton* _button;
}

//---------------------------------------------------------
// Initialize:
//---------------------------------------------------------
- (instancetype)initWithAPIManager:(id<PROAPIAccessing>)apiManager
                      parentPlugin:(id)parentPlugin
                          buttonID:(UInt32)buttonID
                       buttonTitle:(NSString*)buttonTitle
{
    int buttonWidth = 200;
    int buttonHeight = 32;
    
    NSRect frameRect = NSMakeRect(0, 0, buttonWidth, buttonHeight); // x y w h
    self = [super initWithFrame:frameRect];
    
    if (self != nil)
    {
        _apiManager = apiManager;
        
        [self registerForDraggedTypes:@[kFinalCutProUTI]];
        
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0] CGColor];
        self.layer.borderColor = [[NSColor grayColor] CGColor];
        self.layer.borderWidth = 2.0;
        
        //---------------------------------------------------------
        // Cache the parent plugin & button ID:
        //---------------------------------------------------------
        _parentPlugin = parentPlugin;
        _buttonID = buttonID;
        
        //---------------------------------------------------------
        // Add the button:
        //---------------------------------------------------------
        /*
        NSButton *button = [[NSButton alloc]initWithFrame:NSMakeRect(0, 0, buttonWidth, buttonHeight)]; // x y w h
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        [button setBezelStyle: NSBezelStyleRounded];
        button.layer.backgroundColor = [NSColor colorWithCalibratedRed:66 green:66 blue:66 alpha:1].CGColor;
        button.layer.shadowColor = [NSColor blackColor].CGColor;
        [button setBordered:YES];
        [button setTitle:buttonTitle];
        [button setTarget:self];
        [button setAction:@selector(buttonPressed)];
        
        _button = button;
        [self addSubview:_button];
         */
    }
    
    return self;
}

//---------------------------------------------------------
// Awake From NIB:
//---------------------------------------------------------
- (void) awakeFromNib {
    NSArray *sortedPasteboardTypes = @[@"com.apple.finalcutpro.xml.v1-10", @"com.apple.finalcutpro.xml.v1-9", @"com.apple.finalcutpro.xml"];
    [self registerForDraggedTypes:sortedPasteboardTypes];
   
}

//---------------------------------------------------------
// Dragging Entered:
//---------------------------------------------------------
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSArray *sortedPasteboardTypes = @[@"com.apple.finalcutpro.xml.v1-10", @"com.apple.finalcutpro.xml.v1-9", @"com.apple.finalcutpro.xml"];
    for (NSPasteboardType pasteboardType in sortedPasteboardTypes) {
        if ( [[[sender draggingPasteboard] types] containsObject:pasteboardType] ) {
            _dragIsOver = true;
            [self needsDisplay];
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pasteboard = [sender draggingPasteboard];
    NSString *finalCutProData = [pasteboard stringForType:kFinalCutProUTI];
    
    // Handle the dropped Final Cut Pro data
    if (finalCutProData) {
        NSLog(@"Dropped Final Cut Pro data: %@", finalCutProData);
    }
    
    return YES;
}

//---------------------------------------------------------
// Dragging Exited:
//---------------------------------------------------------
- (void)draggingExited:(nullable id <NSDraggingInfo>)sender {
    _dragIsOver = false;
    [self needsDisplay];
}

//---------------------------------------------------------
// Deallocates the memory occupied by the receiver:
//---------------------------------------------------------
- (void)dealloc
{
    if (_button) {
        [_button release];
    }
 
    [super dealloc];
}

//---------------------------------------------------------
// Draw the NSView:
//---------------------------------------------------------
- (void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    [super drawRect:dirtyRect];
    if (_dragIsOver)
    {
        [[[NSColor keyboardFocusIndicatorColor] colorWithAlphaComponent:0.25] set];
        NSRectFill(NSInsetRect(self.bounds, 1, 1));
    }
    [NSGraphicsContext restoreGraphicsState];
}



//---------------------------------------------------------
// Because custom views are hosted in an overlay window,
// the first click on them will normally just make the
// overlay window be the key window, and it will require a
// second click in order to actually tell the view to
// start responding. By returning YES from this method, the
// first click begins user interaction with the view.
//---------------------------------------------------------
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

@end


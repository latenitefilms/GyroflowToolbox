//
//  CustomButtonView.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 29/01/2023.
//

#import "CustomDropZoneView.h"
#import <FxPlug/FxPlugSDK.h>

@interface CustomDropZoneView ()

@property (nonatomic) bool dragIsOver;

@end

@implementation CustomDropZoneView {
    NSButton* _button;
}

//---------------------------------------------------------
// Initialize:
//---------------------------------------------------------
- (instancetype)initWithParentPlugin:(id)parentPlugin
                            buttonID:(UInt32)buttonID
                         buttonTitle:(NSString*)buttonTitle
{
    int buttonWidth = 200;
    int buttonHeight = 32;
    
    NSRect frameRect = NSMakeRect(0, 0, buttonWidth, buttonHeight); // x y w h
    self = [super initWithFrame:frameRect];
    
    if (self != nil)
    {
        NSArray *sortedPasteboardTypes = @[NSPasteboardTypeFileURL, @"com.apple.finalcutpro.xml.v1-11", @"com.apple.finalcutpro.xml.v1-10", @"com.apple.finalcutpro.xml.v1-9", @"com.apple.finalcutpro.xml", @"com.apple.flexo.proFFPasteboardUTI"];
        [self registerForDraggedTypes:sortedPasteboardTypes];
        
        self.wantsLayer                 = YES;
        self.layer.backgroundColor      = [[NSColor colorWithRed:0.11 green:0.11 blue:0.11 alpha:1.0] CGColor];
        self.layer.borderColor          = [[NSColor blackColor] CGColor];
        self.layer.borderWidth          = 1.0;
        
        //---------------------------------------------------------
        // Cache the parent plugin & button ID:
        //---------------------------------------------------------
        _parentPlugin = parentPlugin;
        _buttonID = buttonID;
    }
    
    return self;
}

//---------------------------------------------------------
// Dragging Entered:
//---------------------------------------------------------
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    
    NSArray *sortedPasteboardTypes = @[NSPasteboardTypeFileURL, @"com.apple.finalcutpro.xml.v1-11", @"com.apple.finalcutpro.xml.v1-10", @"com.apple.finalcutpro.xml.v1-9", @"com.apple.finalcutpro.xml"];
    for (NSPasteboardType pasteboardType in sortedPasteboardTypes) {
        if ( [[[sender draggingPasteboard] types] containsObject:pasteboardType] ) {
            _dragIsOver = true;
            [self needsDisplay];
            return NSDragOperationCopy;
        }
    }
    
    return NSDragOperationNone;
}

//---------------------------------------------------------
// Prepare for Drag Operation:
//---------------------------------------------------------
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

//---------------------------------------------------------
// Perform Drag Operation:
//---------------------------------------------------------
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pasteboard = [sender draggingPasteboard];

    if ([[pasteboard types] containsObject:NSPasteboardTypeFileURL]) {
        NSArray *classArray = [NSArray arrayWithObject:[NSURL class]];
        NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:NSPasteboardURLReadingFileURLsOnlyKey];
        NSArray *fileURLs = [pasteboard readObjectsForClasses:classArray options:options];
        for (NSURL *fileURL in fileURLs) {
            //---------------------------------------------------------
            // Trigger Dropped File Method:
            //---------------------------------------------------------
            //NSLog(@"[Gyroflow Toolbox Renderer] Dropped file path: %@", [fileURL path]);
            
            //---------------------------------------------------------
            // Create a new security-scoped bookmark:
            //---------------------------------------------------------
            NSError *bookmarkError = nil;
            NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
            NSData *bookmarkData = [fileURL bookmarkDataWithOptions:bookmarkOptions
                                     includingResourceValuesForKeys:nil
                                                      relativeToURL:nil
                                                              error:&bookmarkError];
            
            if (bookmarkError != nil) {
                NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Unable to create security-scoped bookmark for dragged file ('%@') due to: %@", fileURL, bookmarkError);
                return NO;
            }
            
            if (bookmarkData == nil) {
                NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Unable to create security-scoped bookmark for dragged file ('%@') due to: Bookmark is nil.", fileURL);
                return NO;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_parentPlugin importDroppedMedia:bookmarkData];
            });
            
            _dragIsOver = false;
            [self needsDisplay];
            
            return YES;
        }
        
    } else {
        NSArray *sortedPasteboardTypes = @[@"com.apple.finalcutpro.xml.v1-11", @"com.apple.finalcutpro.xml.v1-10", @"com.apple.finalcutpro.xml.v1-9", @"com.apple.finalcutpro.xml"];
        for (NSPasteboardType pasteboardType in sortedPasteboardTypes) {
            if ( [[pasteboard types] containsObject:pasteboardType] ) {
                //---------------------------------------------------------
                // Trigger Dropped FCPXML Method:
                //---------------------------------------------------------
                NSData *data = [pasteboard dataForType:pasteboardType];
                NSString *finalCutProData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

                //NSLog(@"[Gyroflow Toolbox Renderer] Dropped Final Cut Pro data: %@", finalCutProData);

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_parentPlugin importDroppedClip:finalCutProData];
                });

                _dragIsOver = false;
                [self needsDisplay];
                
                return YES;
            }
        }
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

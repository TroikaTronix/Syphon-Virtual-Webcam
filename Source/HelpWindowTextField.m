//
//  HelpWindowTextFieild.m
//  Syphon Virtual Webcam
//
//  Created by Mark Coniglio on 6/8/20.
//

#import "HelpWindowTextField.h"

//@interface NSMutableAttributedString (SetAsLinkSupport)
//
//- (BOOL)setAsLink:(NSString*)textToFind linkURL:(NSString*)linkURL;
//
//@end
//
//
//@implementation NSMutableAttributedString (SetAsLinkSupport)
//
//- (BOOL)setAsLink:(NSString*)textToFind linkURL:(NSString*)linkURL {
//
//     NSRange foundRange = [self.mutableString rangeOfString:textToFind];
//     if (foundRange.location != NSNotFound) {
//         [self addAttribute:NSLinkAttributeName value:linkURL range:foundRange];
//         return YES;
//     }
//     return NO;
//}
//
//@end

@implementation HelpWindowTextFieild

- (void) awakeFromNib
{
	CGFloat width = 600;
	CGFloat height = 680;
	CGFloat margin = 20.0f;
	
    [[self window] setContentSize:NSMakeSize(width, height)];
	[self setFrameSize:NSMakeSize(width-margin*2, height-margin*2)];
	
	NSURL* url = [[NSBundle mainBundle] URLForResource:@"Welcome" withExtension:@"rtf"];
	NSError* err = NULL;
	NSDictionary* options = @{ NSDocumentTypeDocumentAttribute : NSRTFTextDocumentType};
	NSAttributedString* rtfText = [[NSAttributedString alloc] initWithURL:url options:options documentAttributes:NULL error:&err];
	[self setAttributedStringValue:rtfText];
}

@end

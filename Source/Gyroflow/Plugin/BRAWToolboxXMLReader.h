//
//  BRAWToolboxXMLReader.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 3/8/2023.
//

#import <Cocoa/Cocoa.h>

@interface BRAWToolboxXMLReader : NSObject <NSXMLParserDelegate>

@property (strong, nonatomic) NSString *currentElement;
@property (strong, nonatomic) NSString *filePath;
@property (strong, nonatomic) NSString *bookmarkData;
@property (nonatomic) BOOL isBRAWToolbox;

- (NSDictionary *)readXML:(NSString *)xmlString;

@end

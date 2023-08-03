//
//  BRAWToolboxXMLReader.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 3/8/2023.
//

#import "BRAWToolboxXMLReader.h"

//---------------------------------------------------------
// BRAW Toolbox XML Reader:
//---------------------------------------------------------

@implementation BRAWToolboxXMLReader

//---------------------------------------------------------
// Read XML file:
//---------------------------------------------------------
- (NSDictionary *)readXML:(NSString *)xmlString {
    self.isBRAWToolbox = NO;
    NSData *data = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:self];
    [parser parse];

    if (self.filePath && self.bookmarkData) {
        return @{@"File Path": self.filePath, @"Bookmark Data": self.bookmarkData};
    }
    return nil;
}

//---------------------------------------------------------
// XML Parser:
//---------------------------------------------------------
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    self.currentElement = elementName;

    if ([elementName isEqualToString:@"filter-video"] && [[attributeDict objectForKey:@"name"] isEqualToString:@"BRAW Toolbox"]) {
        self.isBRAWToolbox = YES;
    }

    if (self.isBRAWToolbox && [elementName isEqualToString:@"param"]) {
        if ([[attributeDict objectForKey:@"name"] isEqualToString:@"File Path"]) {
            self.filePath = [attributeDict objectForKey:@"value"];
        } else if ([[attributeDict objectForKey:@"name"] isEqualToString:@"Bookmark Data"]) {
            self.bookmarkData = [attributeDict objectForKey:@"value"];
        }
    }
}

//---------------------------------------------------------
// XML Parser:
//---------------------------------------------------------
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    self.currentElement = nil;
    if ([elementName isEqualToString:@"filter-video"]) {
        self.isBRAWToolbox = NO;
    }
}

//---------------------------------------------------------
// Dealloc:
//---------------------------------------------------------
- (void)dealloc {
    [_currentElement release];
    [_filePath release];
    [_bookmarkData release];
    
    [super dealloc];
}

@end

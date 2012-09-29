//
//  REFirmwareUpdater.m
//  Retrode
//
//  Created by Christoph Leimbrock on 29.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "REFirmwareUpdater.h"
#import "NSString+NSRangeAdditions.h"

NSString * const REFirmwareUpdaterDidReloadVersions = @"RUFirmwareUpdaterDidReloadVersions";

#pragma mark Updater Constants
#define kREUpdatePageURLString @"http://www.retrode.org/firmware"

#pragma mark -
@interface REFirmware ()
@property (strong) NSString *version;
@property (strong) NSString *deviceVersion;
@property (strong) NSURL    *url;
@property (strong) NSArray  *releaseNotes;
@property (strong) NSDate   *releaseDate;
@end
@interface REFirmwareUpdater ()
@property (strong, readwrite) NSMutableArray *availableFirmwareVersions;
@end
@implementation REFirmwareUpdater

+ (REFirmwareUpdater*)sharedFirmwareUpdater
{
    static id sharedFirmwareUpdater = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedFirmwareUpdater = [[REFirmwareUpdater alloc] init];
        [sharedFirmwareUpdater setAvailableFirmwareVersions:[NSMutableArray array]];
    });
    return sharedFirmwareUpdater;
}

- (BOOL)updateAvailableFirmwareVersionsWithError:(NSError**)outError
{
    NSError       *error     = outError != NULL ? *outError : nil;
    NSURL         *updateURL = [NSURL URLWithString:kREUpdatePageURLString];
    NSXMLDocument *document  = [[NSXMLDocument alloc] initWithContentsOfURL:updateURL options:NSXMLDocumentTidyHTML error:&error];
    if(document == nil)
    {
        DLog(@"Could not download or parse update page.");
        DLog(@"%@", error);
        return NO;
    }
    
    NSArray *releaseNodes = [document nodesForXPath:@"/html/body/div/div/table/tr[2]/td[2]/div/div[2]/pre" error:&error];
    if(releaseNodes == nil)
    {
        DLog(@"Could not get release notes.");
        DLog(@"%@", error);
        return NO;
    }
    
    // Parse firmware release notes
    NSString *releaseNotes    = [[releaseNodes lastObject] objectValue];
    NSString *versionPattern  = @"v\\d+\\.\\d+\\w*(\\s\\w+)?";
    NSString *datePattern     = @"(?<=\\()(\\d{4}(-\\d{2}){0,2})(?=\\)\\n)";
    NSString *notesPattern    = @"(?<=-\\s)(.*)(?=\\n)((\\n\\s\\s.*)(?=\\n))*";
    NSString *firmwarePattern = [NSString stringWithFormat:@"%@.*$\\n(^.+$\\n)*", versionPattern];
    NSMutableDictionary *versionsDict      = [NSMutableDictionary dictionary];
    NSRegularExpression *regularExpression = [NSRegularExpression
                                              regularExpressionWithPattern:firmwarePattern
                                              options:NSRegularExpressionAnchorsMatchLines
                                              error:nil];
    [regularExpression enumerateMatchesInString:releaseNotes options:0 range:[releaseNotes fullRange] usingBlock:
     ^ (NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop)
     {
         NSString *version = [[self resultOfPatternMatching:versionPattern inRange:[result range] ofString:releaseNotes] lastObject];
         NSString *date    = [[self resultOfPatternMatching:datePattern inRange:[result range] ofString:releaseNotes] lastObject];
         NSArray  *notes   = [self resultOfPatternMatching:notesPattern inRange:[result range] ofString:releaseNotes];
         
         [versionsDict setValue:@{ @"date" : date, @"notes" : notes} forKey:version];
     }];
    
    // Parse download links
    NSArray *retrode2FirmwareNodes = [document nodesForXPath:@"/html/body/div/div/table/tr[2]/td[2]/div/div[2]/ul[2]/li/a" error:&error];
    if(!retrode2FirmwareNodes)
    {
        DLog(@"Could not get firmware nodes for retrode version 2");
        DLog(@"%@", error);
    }
    
    NSArray *retrode1FirmwareNodes = [document nodesForXPath:@"/html/body/div/div/table/tr[2]/td[2]/div/div[2]/ul[3]/li/a" error:&error];
    if(!retrode1FirmwareNodes)
    {
        DLog(@"Could not get firmware nodes for retrode version 1");
        DLog(@"%@", error);
    }
    
    if(retrode1FirmwareNodes == nil && retrode2FirmwareNodes == nil)
    {
        return NO;
    }
    
    [self setAvailableFirmwareVersions:[NSMutableArray array]];
    
    NSString *retrodeVersionPattern  = @"(?<=files/firmware/Retrode)\\d";
    NSString *firmwareVersionPattern = [versionPattern stringByReplacingOccurrencesOfString:@"\\s" withString:@"-"];
    void (^ parseDownloadLinksBlock) (id, NSUInteger, BOOL *) = ^(NSXMLNode *node, NSUInteger idx, BOOL *stop) {
        NSString   *link     = [[[node nodesForXPath:@"./@href" error:nil] lastObject] objectValue];
        NSRange    fullRange = [link fullRange];
        NSString *retrodeVersion  = [[self resultOfPatternMatching:retrodeVersionPattern inRange:fullRange ofString:link] lastObject];
        NSString *firmwareVersion = [[self resultOfPatternMatching:firmwareVersionPattern inRange:fullRange ofString:link] lastObject];
        firmwareVersion = [firmwareVersion stringByReplacingOccurrencesOfString:@"-" withString:@" "];
        
        if(retrodeVersion != nil && firmwareVersion != nil)
        {
            NSDictionary *releaseInfo = [versionsDict valueForKey:firmwareVersion];
            if(releaseInfo)
            {
                REFirmware *firmware = [[REFirmware alloc] init];
                [firmware setDeviceVersion:retrodeVersion];
                [firmware setVersion:firmwareVersion];
                [firmware setReleaseNotes:[releaseInfo valueForKey:@"notes"]];
                [firmware setUrl:[NSURL URLWithString:link]];
                NSDate *date = [NSDate dateWithString:[releaseInfo valueForKey:@"date"]];
                [firmware setReleaseDate:date];
                
                [(NSMutableArray*)[self availableFirmwareVersions] addObject:firmware];
            }
        }
    };
    
    [retrode1FirmwareNodes enumerateObjectsUsingBlock:parseDownloadLinksBlock];
    [retrode2FirmwareNodes enumerateObjectsUsingBlock:parseDownloadLinksBlock];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:REFirmwareUpdaterDidReloadVersions object:self];
    
    return YES;
}
#pragma mark - Helper
- (NSArray*)resultOfPatternMatching:(NSString*)pattern inRange:(NSRange)range ofString:(NSString*)string
{
    NSRegularExpression *regEx   = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray             *result  = [regEx matchesInString:string options:0 range:range];
    NSMutableArray      *values  = [NSMutableArray arrayWithCapacity:[result count]];
    [result enumerateObjectsUsingBlock:^(NSTextCheckingResult *result, NSUInteger idx, BOOL *stop) {
        NSString  *version = [string substringWithRange:[result range]];
        [values addObject:[version stringByReplacingOccurrencesOfString:@"\n " withString:@""]];
    }];
    return values;
}
@end
@implementation REFirmware
- (NSString*)description
{
    unsigned long address = (unsigned long)self;
    return [NSString stringWithFormat:@"<%@: 0x%lx> version <%@> for device type %@. Download %@", [self className], address, [self version], [self deviceVersion], [self url]];
}
@end
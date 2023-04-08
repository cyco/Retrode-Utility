//
//  RUFirmwareUpdater.m
//  Retrode Utility
//
//  Created by Christoph Leimbrock on 29.09.12.
//  Copyright (c) 2012 Christoph Leimbrock. All rights reserved.
//

#import "RUFirmwareUpdater.h"

#import "NSString+NSRangeAdditions.h"

#import "RURetrode_Configuration.h"
#import "RURetrode_IOLevel.h"

#pragma mark Updater Constants
NSString * const RUFirmwareUpdaterDidReloadVersions = @"RUFirmwareUpdaterDidReloadVersions";
NSString * const RUFirmwareUpdateErrorDomain = @"RUFirmwareUpdateErrorDomain";
const NSInteger kRUFirmwareUpdateErrorOtherUpdateInProgress   = 1000;
const NSInteger kRUFirmwareUpdateErrorDeviceVersionMismatch   = 1001;
const NSInteger kRUFirmwareUpdateErrorVersionAlreadyInstalled = 1002;
const NSInteger kRUFirmwareUpdateErrorRetrodeNotConnected     = 1003;
const NSInteger kRUFirmwareUpdateErrorRetrodeNotInDFU         = 1004;
const NSInteger kRUFirmwareUpdateErrorExtrationFailed         = 1005;
const NSInteger kRUFirmwareUpdateErrorNoFirmwareFile          = 1006;
const NSInteger kRUFirmwareUpdateErrorMultipleFirmwareFiles   = 1007;
const NSInteger kRUFirmwareUpdateErrorNoDFUDevice             = 1008;
const NSInteger kRUFirmwareUpdateErrorDFUProgrammerFail       = 1009;
const NSInteger kRUFirmwareUpdateErrorFirmwareNotFonud        = 1010;

#define kRUUpdatePageURLString @"http://www.retrode.org/firmware"

#pragma mark -
@interface RUFirmware ()
@property (strong) NSString *version;
@property (strong) NSString *deviceVersion;
@property (strong) NSURL    *url;
@property (strong) NSArray  *releaseNotes;
@property (strong) NSDate   *releaseDate;
@end
@interface RUFirmwareUpdater ()
@property (strong, readwrite) NSMutableArray      *availableFirmwareVersions;
@property (strong, readwrite) NSMutableDictionary *currentFirmwareUpdate;
@end
@implementation RUFirmwareUpdater

+ (RUFirmwareUpdater*)sharedFirmwareUpdater
{
    static id sharedFirmwareUpdater = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedFirmwareUpdater = [[RUFirmwareUpdater alloc] init];
        [sharedFirmwareUpdater setAvailableFirmwareVersions:[NSMutableArray array]];
    });
    return sharedFirmwareUpdater;
}
- (RUFirmware*)makeCustomFirmwareWithURL:(NSURL*)file forRetrode:(RURetrode*)retrode {
    RUFirmware *firmware = [[RUFirmware alloc] init];
    firmware.version = @"custom";
    firmware.deviceVersion = retrode.deviceVersion;
    firmware.releaseDate = nil;
    firmware.releaseNotes = @[];
    firmware.url = file;
    return firmware;
}

- (BOOL)updateAvailableFirmwareVersionsWithError:(NSError**)outError
{
    NSURL         *updateURL = [NSURL URLWithString:kRUUpdatePageURLString];
    NSXMLDocument *document  = [[NSXMLDocument alloc] initWithContentsOfURL:updateURL options:NSXMLDocumentTidyHTML error:outError];
    if(document == nil)
    {
        DLog(@"Could not download or parse update page.");
        DLog(@"%@", outError!=NULL?*outError:nil);
        return NO;
    }

    NSArray *releaseNodes = [document nodesForXPath:@"/html/body/div/div/table/tr[2]/td[2]/div/div[2]/pre" error:outError];
    if(releaseNodes == nil || releaseNodes.count == 0)
    {
        DLog(@"Could not get release notes.");
        DLog(@"%@", outError!=NULL?*outError:nil);
        return NO;
    }

    // Parse firmware release notes
    NSString *releaseNotes    = [[releaseNodes lastObject] objectValue];
    NSString *versionPattern  = @"(?<=v)\\d+\\.\\d+\\w*(\\sbeta(\\s\\d+)?)?";
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
         NSString *version = [[self RU_resultOfPatternMatching:versionPattern inRange:[result range] ofString:releaseNotes] objectAtIndex:0];
         NSString *date    = [[self RU_resultOfPatternMatching:datePattern inRange:[result range] ofString:releaseNotes] objectAtIndex:0];
         NSArray  *notes   = [self RU_resultOfPatternMatching:notesPattern inRange:[result range] ofString:releaseNotes];
         [versionsDict setValue:@{ @"date" : date, @"notes" : notes} forKey:version];
     }];

    // Parse download links
    NSArray *retrode2FirmwareNodes = [document nodesForXPath:@"/html/body/div/div/table/tr[2]/td[2]/div/div[2]/ul[2]/li/a" error:outError];
    if(!retrode2FirmwareNodes)
    {
        DLog(@"Could not get firmware nodes for retrode version 2");
        DLog(@"%@", outError!=NULL?*outError:nil);
    }

    NSArray *retrode1FirmwareNodes = [document nodesForXPath:@"/html/body/div/div/table/tr[2]/td[2]/div/div[2]/ul[3]/li/a" error:outError];
    if(!retrode1FirmwareNodes)
    {
        DLog(@"Could not get firmware nodes for retrode version 1");
        DLog(@"%@", outError!=NULL?*outError:nil);
    }

    if(retrode1FirmwareNodes == nil && retrode2FirmwareNodes == nil)
    {
        return NO;
    }

    NSMutableArray *availableFirmwareVersions = [NSMutableArray array];

    NSString *retrodeVersionPattern  = @"(?<=files/firmware/Retrode)\\d";
    NSString *firmwareVersionPattern = [versionPattern stringByReplacingOccurrencesOfString:@"\\s" withString:@"-"];
    void (^ parseDownloadLinksBlock) (id, NSUInteger, BOOL *) = ^(NSXMLNode *node, NSUInteger idx, BOOL *stop) {
        NSString   *link     = [[[node nodesForXPath:@"./@href" error:nil] lastObject] objectValue];
        NSRange    fullRange = [link fullRange];
        NSString *retrodeVersion  = [[self RU_resultOfPatternMatching:retrodeVersionPattern inRange:fullRange ofString:link] lastObject];
        NSString *firmwareVersion = [[self RU_resultOfPatternMatching:firmwareVersionPattern inRange:fullRange ofString:link] lastObject];
        firmwareVersion = [firmwareVersion stringByReplacingOccurrencesOfString:@"-" withString:@" "];

        if(retrodeVersion != nil && firmwareVersion != nil)
        {
            NSDictionary *releaseInfo = [versionsDict valueForKey:firmwareVersion];
            if(releaseInfo)
            {
                RUFirmware *firmware = [[RUFirmware alloc] init];
                [firmware setDeviceVersion:retrodeVersion];
                [firmware setVersion:firmwareVersion];
                [firmware setReleaseNotes:[releaseInfo valueForKey:@"notes"]];
                [firmware setUrl:[NSURL URLWithString:link]];

                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:@"yyyy-MM-dd"];
                NSDate *date = [dateFormatter dateFromString:[releaseInfo valueForKey:@"date"]];
                [firmware setReleaseDate:date];

                [availableFirmwareVersions addObject:firmware];
            } else DLog(@"No version info for %@", firmwareVersion);
        }
    };

    [retrode1FirmwareNodes enumerateObjectsUsingBlock:parseDownloadLinksBlock];
    [retrode2FirmwareNodes enumerateObjectsUsingBlock:parseDownloadLinksBlock];

    [(NSMutableArray*)availableFirmwareVersions sortUsingComparator:^NSComparisonResult(RUFirmware *obj1, RUFirmware *obj2) {
        NSComparisonResult deviceVersionResult = [[obj2 deviceVersion] compare:[obj1 deviceVersion]];
        if(deviceVersionResult == NSOrderedSame)
            deviceVersionResult = [[obj2 version] compare:[obj1 version]];
        return deviceVersionResult;
    }];

    [self setAvailableFirmwareVersions:availableFirmwareVersions];
    [[NSNotificationCenter defaultCenter] postNotificationName:RUFirmwareUpdaterDidReloadVersions object:self];

    return YES;
}

- (void)installFirmware:(RUFirmware*)firmware toRetrode:(RURetrode*)retrode withCallback:(void (^)(double, id))callback
{
    DLog();
    NSAssert(firmware!=nil && retrode!=nil, @"Invalid method call, you need to pass a firmware and a retrode.");

    if([self currentFirmwareUpdate] != nil)
    {
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorOtherUpdateInProgress userInfo:nil];
        callback(-1.0, error);
        return;
    }

    [self setCurrentFirmwareUpdate:[NSMutableDictionary dictionary]];

    if([[retrode deviceVersion] isNotEqualTo:[firmware deviceVersion]])
    {
        [self setCurrentFirmwareUpdate:nil];
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorDeviceVersionMismatch userInfo:nil];
        callback(-1.0, error);
        return;
    }

    if([[retrode firmwareVersion] isEqualTo:[firmware version]])
    {
        [self setCurrentFirmwareUpdate:nil];
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorVersionAlreadyInstalled userInfo:nil];
        callback(-1.0, error);
        return;
    }

    if([retrode deviceData] == NULL)
    {
        [self setCurrentFirmwareUpdate:nil];
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorRetrodeNotConnected userInfo:nil];
        callback(-1.0, error);
        return;
    }

    if(![retrode DFUMode])
    {
        [self setCurrentFirmwareUpdate:nil];
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorRetrodeNotInDFU userInfo:nil];
        callback(-1.0, error);
        return;
    }

    [[self currentFirmwareUpdate] setObject:firmware forKey:@"firmware"];
    [[self currentFirmwareUpdate] setObject:retrode  forKey:@"retrode"];
    [[self currentFirmwareUpdate] setObject:callback forKey:@"callback"];

    NSURL *firmwareURL = [firmware url];
    if([firmwareURL isFileURL]) {
        [self RU_installFirmwareAtPath:[firmwareURL path]];
        return;
    }

    NSURLRequest  *request     = [NSURLRequest requestWithURL:firmwareURL];
    NSURLDownload *download    = [[NSURLDownload alloc] initWithRequest:request delegate:self];
    NSString      *destination = [NSTemporaryDirectory() stringByAppendingString:@"Retrode Firmware.zip"];

    [download setDeletesFileUponFailure:YES];
    [download setDestination:destination allowOverwrite:YES];
    [[self currentFirmwareUpdate] setObject:destination forKey:@"destination"];
}
#define CurrentCallback ((void (^)(double, id))[[self currentFirmwareUpdate] objectForKey:@"callback"])

- (void)RU_extractAndInstallFirmwareAtPath:(NSString*)path
{
    DLog();
    CurrentCallback(0.0, @"Extracting");

    NSString *targetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Retrode Firmware/"];
    [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];

    NSTask *cmd = [[NSTask alloc] init];
    [cmd setLaunchPath:@"/usr/bin/ditto"];
    [cmd setArguments:@[@"-v",@"-x",@"-k",@"--rsrc", path, targetPath]];
    [cmd launch];
    [cmd waitUntilExit];
    if([cmd terminationStatus] != 0)
    {
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorExtrationFailed userInfo:nil];
        CurrentCallback(-1.0, error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    CurrentCallback(1.0, @"Extracting");

    [self RU_installFirmwareAtPath:targetPath];
}

- (void)RU_installFirmwareAtPath:(NSString*)path
{
    NSError *error = nil;
    if([[path pathExtension] isEqualTo:@""])
    {
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
        if(!contents)
        {
            CurrentCallback(-1.0, error);
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            return;
        }

        contents = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            return [[evaluatedObject pathExtension] isEqualToString:@"hex"];
        }]];

        if([contents count] == 0)
        {
            error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorNoFirmwareFile userInfo:nil];
            CurrentCallback(-1.0, error);
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            return;
        }

        if([contents count] > 1)
        {
            error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorMultipleFirmwareFiles userInfo:nil];
            CurrentCallback(-1.0, error);
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            return;
        }

        path = [path stringByAppendingPathComponent:[contents lastObject]];
    }
    CurrentCallback(0.25, @"Checking DFU");
    NSString *dfuProgrammerPath = [[NSBundle mainBundle] pathForResource:@"dfu-programmer" ofType:nil];
    NSTask   *cmd = [[NSTask alloc] init];
    [cmd setLaunchPath:dfuProgrammerPath];
    [cmd setArguments:@[@"at90usb646", @"get", @"product-revision"]];
    [cmd launch];
    [cmd waitUntilExit];
    if([cmd terminationStatus] == 1)
    {
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorNoDFUDevice userInfo:nil];
        CurrentCallback(-1.0, error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    if(![[NSFileManager defaultManager] fileExistsAtPath:path]) {

        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorFirmwareNotFonud userInfo:nil];
        CurrentCallback(-1.0, error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    if([cmd terminationStatus] != 0)
    {
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorDFUProgrammerFail userInfo:nil];
        CurrentCallback(-1.0, error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    CurrentCallback(0.5, @"Erasing Firmware");
    cmd = [[NSTask alloc] init];
    [cmd setLaunchPath:dfuProgrammerPath];
    [cmd setArguments:@[@"at90usb646", @"erase"]];
    [cmd launch];
    [cmd waitUntilExit];
    if([cmd terminationStatus] != 0)
    {
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorDFUProgrammerFail userInfo:nil];
        CurrentCallback(-1.0, error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }

    CurrentCallback(0.5, @"Flashing Firmware");
    cmd = [[NSTask alloc] init];
    [cmd setLaunchPath:dfuProgrammerPath];
    [cmd setArguments:@[@"at90usb646", @"flash", path]];
    [cmd launch];
    [cmd waitUntilExit];
    if([cmd terminationStatus] != 0)
    {
        // TODO: create user info for error
        NSError *error = [NSError errorWithDomain:RUFirmwareUpdateErrorDomain code:kRUFirmwareUpdateErrorDFUProgrammerFail userInfo:nil];
        CurrentCallback(-1.0, error);
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        return;
    }
    CurrentCallback(1.0, @"Done");
}

#pragma mark - Helper
- (NSArray*)RU_resultOfPatternMatching:(NSString*)pattern inRange:(NSRange)range ofString:(NSString*)string
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
#pragma mark - NSURLDownloadDelegate
- (void)downloadDidBegin:(NSURLDownload *)download
{
    DLog();
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    DLog();
    CurrentCallback(-1.0, error);
    [self setCurrentFirmwareUpdate:nil];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
    DLog();
    NSUInteger receivedData   = [[[self currentFirmwareUpdate] objectForKey:@"receivedData"] unsignedIntegerValue];
    NSUInteger expectedLength = [[[self currentFirmwareUpdate] objectForKey:@"expectedLength"] unsignedIntegerValue];
    receivedData += length;
    double progress = (double)receivedData / expectedLength;

    CurrentCallback(progress, @"Downloading");

    [[self currentFirmwareUpdate] setObject:@(receivedData) forKey:@"receivedData"];
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
    [[self currentFirmwareUpdate] setObject:@([response expectedContentLength]) forKey:@"expectedLength"];
    DLog(@"Got response");
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    DLog();
    CurrentCallback(1.0, @"Downloading");
    [self RU_extractAndInstallFirmwareAtPath:[[self currentFirmwareUpdate] objectForKey:@"destination"]];
}
@end

@implementation RUFirmware
- (NSString*)description
{
    unsigned long address = (unsigned long)self;
    return [NSString stringWithFormat:@"<%@: 0x%lx> version <%@> for device type %@. Download %@", [self className], address, [self version], [self deviceVersion], [self url]];
}
@end

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <getopt.h>
#import <stdio.h>
#import "BSONSerialization.h"

@interface LCSDeltaMessage : NSObject
@property (readonly) NSArray* deletableOids;
@property (readonly) NSArray* insertableOids;
@property (readonly) NSArray* insertableMetadata;
@end

@implementation LCSDeltaMessage

- (id)initWithDeletableOids:(NSArray*)deletableOids insertableOids:(NSArray*)insertableOids insertableMetadata:(NSArray*)insertableMetadata {
    self = [super init];

    if (self) {
        NSAssert([insertableOids count] == [insertableMetadata count], @"Oids and metadata array must be of the same length.");
        _deletableOids = deletableOids;
        _insertableOids = insertableOids;
        _insertableMetadata = insertableMetadata;
    }

    return self;
}

- (id)initWithMessages:(NSArray*)messages {
    NSMutableArray *deletableOids = [NSMutableArray array];
    NSMutableArray *insertableOids = [NSMutableArray array];
    NSMutableArray *insertableMetadata = [NSMutableArray array];

    for (LCSDeltaMessage *message in messages) {
        [deletableOids addObjectsFromArray:message.deletableOids];
        [insertableOids addObjectsFromArray:message.insertableOids];
        [insertableMetadata addObjectsFromArray:message.insertableMetadata];
    }

    return [self initWithDeletableOids:deletableOids insertableOids:insertableOids insertableMetadata:insertableMetadata];
}

- (id)initWithDeletableOids:(NSArray*)deletableOids {
    return [self initWithDeletableOids:deletableOids insertableOids:[NSArray array] insertableMetadata:[NSArray array]];
}

- (NSData*)BSONRepresentation {
    NSDictionary *message = @{
        // FIXME: Make the port name changeable.
        @"port": "default",
        @"item": @{
            @"type": @"delta",
            @"date": [NSDate date],
            @"deletes": _deletableOids,
            @"inserts": _insertableOids,
            @"data": [NSDictionary dictionaryWithObjects:_insertableMetadata forKeys:_insertableOids]
        }
    };

    return [message BSONRepresentation];
}

@end

@interface LCSSpotlightResultItem : NSObject {
    NSMetadataItem* _item;
}
@property (readonly) NSString* oid;
@end

@implementation LCSSpotlightResultItem

- (id)initWithItem:(NSMetadataItem*)item {
    self = [super init];

    if (self) {
        _item = item;
        _oid = nil;
    }

    return self;
}

- (LCSDeltaMessage*)update {
    NSArray *deletableOids = _oid ? [NSArray arrayWithObject:_oid] : [[NSArray alloc] init];
    NSDictionary *spotlightMeta = [_item valuesForAttributes:[[self class] attributeKeys]];

    NSString *path = [spotlightMeta objectForKey:@"kMDItemPath"];
    if (!path) {
        NSLog(@"Oops, path not present in metadata item.");
        return nil;
    }

    // FIXME: rewrite properly with error handling
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:(id)spotlightMeta format:NSPropertyListBinaryFormat_v1_0 options:NSPropertyListImmutable error:nil];

    unsigned char md[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([data bytes], (CC_LONG)[data length], md);
    NSString* base64 = [[NSData dataWithBytes:md length:CC_SHA1_DIGEST_LENGTH] base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    _oid = base64;
    // EOFIXME.

    NSDictionary *meta = [NSDictionary dictionaryWithObjectsAndKeys: spotlightMeta, @"spotlight", path, @"path", nil];
    NSArray *insertableMeta = [NSArray arrayWithObject:meta];
    NSArray *insertableOids = [NSArray arrayWithObject:_oid];

    return [[LCSDeltaMessage alloc] initWithDeletableOids:deletableOids insertableOids:insertableOids insertableMetadata:insertableMeta];
}

- (LCSDeltaMessage*)delete {
    if (!_oid) {
        // There is no guarantee that _oid is initialized. This happens e.g. when files are created and immediately deleted again.
        return nil;
    }

    NSString* oid = _oid;
    _oid = nil;
    return [[LCSDeltaMessage alloc] initWithDeletableOids:[NSArray arrayWithObject:oid]];
}

+ (NSArray*)attributeKeys {
    static NSArray *keys;
    if (!keys) {
        keys = [NSArray arrayWithObjects:
                @"kMDItemContentCreationDate",
                @"kMDItemContentModificationDate",
                @"kMDItemContentType",
                @"kMDItemContentTypeTree",
                @"kMDItemDateAdded",
                @"kMDItemDisplayName",
                @"kMDItemFSContentChangeDate",
                @"kMDItemFSCreationDate",
                @"kMDItemFSCreatorCode",
                @"kMDItemFSFinderFlags",
                @"kMDItemFSHasCustomIcon",
                @"kMDItemFSInvisible",
                @"kMDItemFSIsExtensionHidden",
                @"kMDItemFSIsStationery",
                @"kMDItemFSLabel",
                @"kMDItemFSName",
                @"kMDItemFSNodeCount",
                @"kMDItemFSOwnerGroupID",
                @"kMDItemFSOwnerUserID",
                @"kMDItemFSSize",
                @"kMDItemFSTypeCode",
                @"kMDItemKind",
                @"kMDItemLogicalSize",
                @"kMDItemPath",
                @"kMDItemPhysicalSize",
                @"kMDItemUserTags",
                nil];

    }
    return keys;
}
@end

@interface LCSSpotlightQueryRunner : NSObject <NSMetadataQueryDelegate>
@end

@implementation LCSSpotlightQueryRunner

NSMetadataQuery *_query;

- (id) initWithQuery:(NSMetadataQuery* )query {
    self = [super init];
    if (self) {
        _query = query;
    }
    return self;
}

- (id) start {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queryUpdateResults:)
                                                 name:NSMetadataQueryGatheringProgressNotification
                                               object:_query];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queryUpdateResults:)
                                                 name:NSMetadataQueryDidUpdateNotification
                                               object:_query];
    [_query setDelegate:self];
    [_query startQuery];
    return self;
}

- (id) stop {
    [_query stopQuery];
    [_query setDelegate:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    return self;
}

- (void) queryUpdateResults:(NSNotification *)notification {
    NSMetadataQuery *query = (NSMetadataQuery *)[notification object];

    [query disableUpdates];

    NSDictionary *userInfo = [notification userInfo];
    NSArray *added = [userInfo objectForKey:NSMetadataQueryUpdateAddedItemsKey];
    NSArray *changed = [userInfo objectForKey:NSMetadataQueryUpdateChangedItemsKey];
    NSArray *removed = [userInfo objectForKey:NSMetadataQueryUpdateRemovedItemsKey];

    unsigned long removedCount = removed ? (unsigned long) [removed count] : 0;
    unsigned long changedCount = changed ? (unsigned long) [changed count] : 0;
    unsigned long addedCount = added ? (unsigned long) [added count] : 0;

    NSMutableArray *deltas = [NSMutableArray arrayWithCapacity:removedCount + changedCount + addedCount];
    if (removed) {
        for (LCSSpotlightResultItem *result in removed) {
            if (![result isKindOfClass:[LCSSpotlightResultItem class]]) {
                continue;
            }

            LCSDeltaMessage* msg = [result delete];
            if (!msg) {
                continue;
            }

            [deltas addObject:msg];
        }
    }
    if (added) {
        for (LCSSpotlightResultItem *result in added) {
            if (![result isKindOfClass:[LCSSpotlightResultItem class]]) {
                continue;
            }

            LCSDeltaMessage* msg = [result update];
            if (!msg) {
                continue;
            }

            [deltas addObject:msg];
        }
    }
    if (changed) {
        for (LCSSpotlightResultItem *result in changed) {
            if (![result isKindOfClass:[LCSSpotlightResultItem class]]) {
                continue;
            }

            LCSDeltaMessage* msg = [result update];
            if (!msg) {
                continue;
            }

            [deltas addObject:msg];
        }
    }

    NSRange range = {
        .location = 0,
        .length = 0
    };
    while (range.location < [deltas count]) {
        range.length = [deltas count] - range.location;
        if (range.length > 8) {
            range.length = 8;
        }
        [self dump:[[LCSDeltaMessage alloc] initWithMessages:[deltas subarrayWithRange:range]]];
        range.location += range.length;
    }

    [query enableUpdates];
}

- (id) metadataQuery:(NSMetadataQuery *)query replacementObjectForResultObject:(NSMetadataItem *)result {
    return [[LCSSpotlightResultItem alloc] initWithItem:result];
}

- (void) dump:(LCSDeltaMessage *) message {
    NSFileHandle *f = [NSFileHandle fileHandleWithStandardOutput];
    NSData *serializedMessage = [message BSONRepresentation];
    [f writeData:serializedMessage];
}

@end

void usage(const char *prog) {
    NSLog(@"%s: [-n] DIR PATTERN", prog);
    exit(1);
}

int main(int argc, char *const argv[]) {
    int native_query = 0, ch = 0;
    const char *prog = argv[0];

    /* options descriptor */
    static struct option longopts[] = {
        { "native-query",   required_argument,  NULL,   'n' },
        { "help",           no_argument,        NULL,   'h' },
        { NULL,             0,                  NULL,   0 }
    };

    while ((ch = getopt_long(argc, argv, "nh", longopts, NULL)) != -1) {
        switch (ch) {
            case 'n':
                native_query = 1;
                break;
            default:
                usage(prog);
                break;
        }
    }
    argc -= optind;
    argv += optind;

    @autoreleasepool {
        if (argc == 2) {
            // Dispatch queue which polls stdin until EOF. For some weird reason we cannot use NSFileHandle
            // readToEndOfFileInBackgroundAndNotify on the stdandard input since that results in EAGAIN errors on stdout :/
            __block bool done = false;
            dispatch_queue_t stdin_reader_queue = dispatch_queue_create("standard input reader", DISPATCH_QUEUE_SERIAL);
            dispatch_async(stdin_reader_queue, ^{
                char buf[1024];
                while(fgets(buf, sizeof(buf), stdin)) {
                    // Do nothing.
                }
                dispatch_sync(dispatch_get_main_queue(), ^{
                    done = true;
                });
            });

            NSString *directory = [NSString stringWithUTF8String:argv[0]];
            NSString *pattern = [NSString stringWithUTF8String:argv[1]];

            if (!native_query) {
                pattern = [NSString stringWithFormat:@"kMDItemFSName like[c] '%@'", pattern];
            }

            NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
            [query setPredicate:[NSPredicate predicateWithFormat:pattern]];
            [query setSearchScopes:[NSArray arrayWithObject:directory]];

            LCSSpotlightQueryRunner *runner = [[[LCSSpotlightQueryRunner alloc] initWithQuery:query] start];
            while (!done) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
            }
            [runner stop];
        }
        else {
            usage(prog);
        }
    }

    return EXIT_SUCCESS;
}

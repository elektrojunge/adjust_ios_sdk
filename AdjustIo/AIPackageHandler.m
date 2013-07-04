//
//  AIPackageHandler.m
//  AdjustIosApp
//
//  Created by Christian Wellenbrock on 03.07.13.
//  Copyright (c) 2013 adeven. All rights reserved.
//

#import "AIPackageHandler.h"
#import "AIRequestHandler.h"
#import "AIActivityPackage.h"
#import "AILogger.h"

static NSString * const kPackageQueueFilename = @"PackageQueue1"; // TODO: rename
static const char * const kInternalQueueName = "io.adjust.PackageQueue1"; // TODO: rename

#pragma mark private interface

@interface AIPackageHandler()

@property (nonatomic, retain) dispatch_queue_t internalQueue;
@property (nonatomic, retain) AIRequestHandler *requestHandler;
@property (nonatomic, retain) NSMutableArray *packageQueue;
@property (nonatomic, retain) dispatch_semaphore_t sendingSemaphore;
@property (nonatomic, assign, getter = isPaused) BOOL paused;

- (void)initInternal;
- (void)addInternal:(AIActivityPackage *)package;
- (void)sendFirstInternal;
- (void)sendNextInternal;

- (void)readPackageQueue;
- (void)writePackageQueue;
- (NSString *)packageQueueFilename;

@end


@implementation AIPackageHandler

#pragma mark public implementation

- (id)init {
    self = [super init];
    if (self == nil) return nil;

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);

    dispatch_async(self.internalQueue, ^{
        [self initInternal];
    });

    return self;
}

- (void)addPackage:(AIActivityPackage *)package {
    dispatch_async(self.internalQueue, ^{
        [self addInternal:package];
    });
}

- (void)sendFirstPackage {
    dispatch_async(self.internalQueue, ^{
        [self sendFirstInternal];
    });
}

- (void)sendNextPackage {
    dispatch_async(self.internalQueue, ^{
        [self sendNextInternal];
    });
}

- (void)closeFirstPackage {
    dispatch_semaphore_signal(self.sendingSemaphore);
}

- (void)pauseSending {
    self.paused = YES;
}

- (void)resumeSending {
    self.paused = NO;
}


#pragma marke private implementation

- (void)initInternal {
    self.requestHandler = [AIRequestHandler handlerWithPackageHandler:self];
    self.sendingSemaphore = dispatch_semaphore_create(1);
    [self readPackageQueue];
}

- (void)addInternal:(AIActivityPackage *)newPackage {
    [self.packageQueue addObject:newPackage];
    [AILogger debug:@"Added package %d (%@)", self.packageQueue.count, newPackage];
    [AILogger verbose:@"%@", newPackage.parameterString];

    [self writePackageQueue];
    [self sendFirstInternal];
}

- (void)sendFirstInternal {
    if (self.packageQueue.count == 0) return;

    if (self.isPaused) {
        [AILogger debug:@"Package handler is paused"];
        return;
    }

    if (dispatch_semaphore_wait(self.sendingSemaphore, DISPATCH_TIME_NOW) != 0) {
        [AILogger debug:@"Package handler is already sending"];
        return;
    }

    AIActivityPackage *activityPackage = [self.packageQueue objectAtIndex:0];
    [self.requestHandler sendPackage:activityPackage];
}

- (void)sendNextInternal {
    [self.packageQueue removeObjectAtIndex:0];
    [self writePackageQueue];
    dispatch_semaphore_signal(self.sendingSemaphore);
    [self sendFirstInternal];
}

- (void)readPackageQueue {
    @try {
        NSString *filename = [self packageQueueFilename];
        id object = [NSKeyedUnarchiver unarchiveObjectWithFile:filename];
        if ([object isKindOfClass:[NSArray class]]) {
            // TODO: check class of packages?
            self.packageQueue = object;
            [AILogger debug:@"Package handler read %d packages", self.packageQueue.count];
            return;
        } else {
            [AILogger error:@"Failed to read package queue"];
        }
    } @catch (NSException *exception) {
        [AILogger error:@"Failed to read package queue (%@)", exception];
    }

    // start with a fresh package queue in case of any exception
    self.packageQueue = [NSMutableArray array];
}

- (void)writePackageQueue {
    NSString *filename = [self packageQueueFilename];
    BOOL result = [NSKeyedArchiver archiveRootObject:self.packageQueue toFile:filename];
    if (result == YES) {
        [AILogger verbose:@"Package handler wrote %d packages", self.packageQueue.count];
    } else {
        [AILogger verbose:@"Failed to write package queue"];
    }
}

- (NSString *)packageQueueFilename {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths objectAtIndex:0];
    NSString *filename = [path stringByAppendingPathComponent:kPackageQueueFilename];
    return filename;
}

@end
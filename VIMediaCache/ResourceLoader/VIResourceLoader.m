//
//  VIResoureLoader.m
//  VIMediaCacheDemo
//
//  Created by Vito on 4/21/16.
//  Copyright © 2016 Vito. All rights reserved.
//

#import "VIResourceLoader.h"
#import "VIMediaDownloader.h"
#import "VIResourceLoadingRequestWorker.h"
#import "VIContentInfo.h"
#import "VIMediaCacheWorker.h"

NSString * const MCResourceLoaderErrorDomain = @"LSFilePlayerResourceLoaderErrorDomain";

@interface VIResourceLoader () <VIResourceLoadingRequestWorkerDelegate>

@property (nonatomic, strong, readwrite) NSURL *url;
@property (nonatomic, strong) VIMediaCacheWorker *cacheWorker;
@property (nonatomic, strong) VIMediaDownloader *mediaDownloader;
@property (nonatomic, strong) NSMutableArray<VIResourceLoadingRequestWorker *> *pendingRequestWorkers;
@property (nonatomic, strong) NSRecursiveLock *pendingRequestWorkersLock;

@property (nonatomic, getter=isCancelled) BOOL cancelled;

@end

@implementation VIResourceLoader


- (void)dealloc {
    [_mediaDownloader cancel];
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
        _cacheWorker = [[VIMediaCacheWorker alloc] initWithURL:url];
        _mediaDownloader = [[VIMediaDownloader alloc] initWithURL:url cacheWorker:_cacheWorker];
        _pendingRequestWorkers = [NSMutableArray array];
        _pendingRequestWorkersLock = [[NSRecursiveLock alloc] init];
    }
    return self;
}

- (instancetype)init {
    NSAssert(NO, @"Use - initWithURL: instead");
    return nil;
}

- (void)addRequest:(AVAssetResourceLoadingRequest *)request {
    BOOL hasPendingRequestWorkers = NO;
    [self.pendingRequestWorkersLock lock];
    hasPendingRequestWorkers = self.pendingRequestWorkers.count > 0;
    [self.pendingRequestWorkersLock unlock];

    if (hasPendingRequestWorkers) {
        [self startNoCacheWorkerWithRequest:request];
    } else {
        [self startWorkerWithRequest:request];
    }
}

- (void)removeRequest:(AVAssetResourceLoadingRequest *)request {
    __block VIResourceLoadingRequestWorker *requestWorker = nil;
    [self.pendingRequestWorkersLock lock];
    [self.pendingRequestWorkers enumerateObjectsUsingBlock:^(VIResourceLoadingRequestWorker *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.request == request) {
            requestWorker = obj;
            *stop = YES;
        }
    }];
    if (requestWorker) {
        [requestWorker finish];
        [self.pendingRequestWorkers removeObject:requestWorker];
    }
    [self.pendingRequestWorkersLock unlock];
}

- (void)cancel {
    [self.mediaDownloader cancel];

    [self.pendingRequestWorkersLock lock];
    [self.pendingRequestWorkers removeAllObjects];
    [self.pendingRequestWorkersLock unlock];
    
    [[VIMediaDownloaderStatus shared] removeURL:self.url];
}

#pragma mark - VIResourceLoadingRequestWorkerDelegate

- (void)resourceLoadingRequestWorker:(VIResourceLoadingRequestWorker *)requestWorker didCompleteWithError:(NSError *)error {
    [self removeRequest:requestWorker.request];
    if (error && [self.delegate respondsToSelector:@selector(resourceLoader:didFailWithError:)]) {
        [self.delegate resourceLoader:self didFailWithError:error];
    }
    BOOL hasPendingRequestWorkers = NO;
    [self.pendingRequestWorkersLock lock];
    hasPendingRequestWorkers = self.pendingRequestWorkers.count > 0;
    [self.pendingRequestWorkersLock unlock];

    if (!hasPendingRequestWorkers) {
        [[VIMediaDownloaderStatus shared] removeURL:self.url];
    }
}

#pragma mark - Helper

- (void)startNoCacheWorkerWithRequest:(AVAssetResourceLoadingRequest *)request {
    [[VIMediaDownloaderStatus shared] addURL:self.url];
    VIMediaDownloader *mediaDownloader = [[VIMediaDownloader alloc] initWithURL:self.url cacheWorker:self.cacheWorker];
    VIResourceLoadingRequestWorker *requestWorker = [[VIResourceLoadingRequestWorker alloc] initWithMediaDownloader:mediaDownloader
                                                                                             resourceLoadingRequest:request];
    [self.pendingRequestWorkersLock lock];
    [self.pendingRequestWorkers addObject:requestWorker];
    [self.pendingRequestWorkersLock unlock];
    requestWorker.delegate = self;
    [requestWorker startWork];
}

- (void)startWorkerWithRequest:(AVAssetResourceLoadingRequest *)request {
    [[VIMediaDownloaderStatus shared] addURL:self.url];
    VIResourceLoadingRequestWorker *requestWorker = [[VIResourceLoadingRequestWorker alloc] initWithMediaDownloader:self.mediaDownloader
                                                                                             resourceLoadingRequest:request];
    [self.pendingRequestWorkersLock lock];
    [self.pendingRequestWorkers addObject:requestWorker];
    [self.pendingRequestWorkersLock unlock];
    requestWorker.delegate = self;
    [requestWorker startWork];
    
}

- (NSError *)loaderCancelledError {
    NSError *error = [[NSError alloc] initWithDomain:MCResourceLoaderErrorDomain
                                                code:-3
                                            userInfo:@{NSLocalizedDescriptionKey:@"Resource loader cancelled"}];
    return error;
}

@end

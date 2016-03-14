//
//  NAWebImageManager.m
//  NAWebImage
//
//  Created by zuopengl on 3/14/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "NAWebImageManager.h"
#import "NAWebDataDownloader.h"



@interface NAWebImageCombinedOperation : NSObject
<
NAWebImageOperation
>
@property (nonatomic, strong) NSOperation *cacheOperation;
@property (nonatomic, copy) NAImageDownloadCancelBlock cancelBlock;

@property (nonatomic, assign, getter=isCancelled) BOOL cancelled;
@end


@interface NAWebImageManager ()
@property (nonatomic, strong, readwrite) NAImageCache *imageCache;
@property (nonatomic, strong, readwrite) NAWebDataDownloader *imageDownloader;

@property (nonatomic, strong, readwrite) NSMutableArray *runningOperations;
@end


@implementation NAWebImageManager

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    static id inst = nil;
    dispatch_once(&onceToken, ^{
        inst = [self new];
    });
    return inst;
}


- (instancetype)init {
    if ((self = [super init])) {
        _imageCache = [NAImageCache sharedImageCache];
        _imageDownloader = [NAWebDataDownloader sharedDownloader];
        
        _runningOperations = [NSMutableArray array];
    }
    return self;
}


- (id<NAWebImageOperation>)na_downloadImageForURL:(NSURL *)url options:(NAWebImageOptions)options progress:(NAImageDownloadProgressBlock)progressBlock completion:(NAImageDownloadCompletedBlock)completedBlock {
    if (!completedBlock) {
        @throw @"completedBlock can not nil";
    }
    
    if ([url isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)url];
    }
    if (![url isKindOfClass:[NSURL class]]) {
        url = nil;
    }
    
    if (!url) {
        completedBlock(nil, url, kNAImageCacheNone, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey:@"url is not valid"}], YES);
        return nil;
    }
    
    __block NAWebImageCombinedOperation *operation = [NAWebImageCombinedOperation new];
    __weak typeof(operation) weakOperation = operation;
    [self.runningOperations addObject:operation];
    operation.cacheOperation = [self.imageCache queryImageForKey:[self na_cacheKeyForURL:url] completion:^(UIImage *image, NAImageCacheType cacheType) {
        if (operation.isCancelled) {
            @synchronized (self.runningOperations) {
                [self.runningOperations removeObject:operation];
            }
            return;
        }
        
        if (!image || (options | NAWebImageRefreshCached)) {
            // not exist in cache, start to download image for url
            NAWebDataDownloadOptions downloadOptions = 0;
            if (options & NAWebImageLowPriority) downloadOptions |= kNAWebDataDownloadLowPriority;
            if (options & NAWebImageProgressiveDownload) downloadOptions |= kNAWebDataDownloadProgressiveDownload;
            if (options & NAWebImageRefreshCached) downloadOptions |= kNAWebDataDownloadUseNSURLCache;
            if (options & NAWebImageContinueInBackground) downloadOptions |= kNAWebDataDownloadContinueInBackground;
            if (options & NAWebImageHandleCookies) downloadOptions |= kNAWebDataDownloadHandleCookies;
            if (options & NAWebImageAllowInvalidSSLCertificates) downloadOptions |= kNAWebDataDownloadAllowInvliadSSLCertificates;
            if (options & NAWebImageHighPriority) downloadOptions |= kNAWebDataDownloadHighPriority;
            if (options & NAWebImageRefreshCached) {
                downloadOptions &= ~kNAWebDataDownloadProgressiveDownload;
                downloadOptions |= kNAWebDataDownloadIgnoreCacheResponse;
            }

            id<NAWebDataOperation> downloadOperation = [self.imageDownloader downloadImageWithURL:url options:downloadOptions progressBlock:^(NSInteger receivedSize, NSInteger expectedSize) {
                safe_async_main_queue_block(progressBlock, receivedSize, expectedSize);
            } completedBlock:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                __weak typeof(weakOperation) strongOperation = weakOperation;
                if (!strongOperation || [strongOperation isCancelled]) {
                    safe_async_main_queue_block(completedBlock, nil, url, kNAImageCacheNone, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey:@"Cancel download operation ..."}], YES);
                } else if (image && finished) {
                    BOOL cacheInDisk = !(options & NAWebImageCacheMemoryOnly);
                    if (cacheInDisk) {
                        [self.imageCache storeImage:image forKey:[self na_cacheKeyForURL:url]];
                    }
                }
                
                safe_async_main_queue_block(completedBlock, image, url, kNAImageCacheNone, error, finished);
                
                if (finished) {
                    @synchronized(self.runningOperations) {
                        [self.runningOperations removeObject:strongOperation];
                    }
                }
            }];
            
            // add cancel block for combined operation
            operation.cancelBlock = ^() {
                [downloadOperation cancel];
                @synchronized(self) {
                    __strong __typeof(weakOperation) strongOperation = weakOperation;
                    if (strongOperation) {
                        [self.runningOperations removeObject:strongOperation];
                    }
                }
            };
        } else if (image) {
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            if (strongOperation && !strongOperation.isCancelled) {
                safe_async_main_queue_block(completedBlock, image, url, cacheType, nil, YES);
            }
            @synchronized(self.runningOperations) {
                [self.runningOperations removeObject:weakOperation];
            }
        } else {
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            if (strongOperation && !strongOperation.isCancelled) {
                safe_async_main_queue_block(completedBlock, nil, url, kNAImageCacheNone, nil, YES);
            }
            @synchronized(self.runningOperations) {
                [self.runningOperations removeObject:weakOperation];
            }
        }
    }];
    
    return operation;
}


- (void)na_saveImageToCache:(UIImage *)image forURL:(NSURL *)url {
    if (!image || !url) {
        return;
    }
    [self.imageCache storeImage:image forKey:[self na_cacheKeyForURL:url]];
}


- (BOOL)na_cachedImageExistForURL:(NSURL *)url {
    return [self.imageCache cacheImageExistsForKey:[self na_cacheKeyForURL:url]];
}


- (NSString *)na_cacheKeyForURL:(NSURL *)url {
    return NACacheKeyForURL(url);
}


- (void)cancelAll {
    @synchronized(self.runningOperations) {
        NSArray *copiedOperations = [self.runningOperations copy];
        [copiedOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeObjectsInArray:copiedOperations];
    }
}


- (BOOL)isRunning {
    BOOL running = NO;
    @synchronized(self.runningOperations) {
        running = ([self.runningOperations count] > 0);
    }
    return running;
}
@end



/**
 *  Implementation of NAWebImageCombinedOperation
 */
@implementation NAWebImageCombinedOperation

- (void)setCancelBlock:(NAImageDownloadCancelBlock)cancelBlock {
    if (self.cancelled) {
        safe_block(cancelBlock);
        cancelBlock = nil;
    } else {
        _cancelBlock = [cancelBlock copy];
    }
}


- (void)cancel {
    self.cancelled = YES;
    
    if (self.cacheOperation) {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    
    safe_block(self.cancelBlock);
    _cancelBlock = nil;
}

@end

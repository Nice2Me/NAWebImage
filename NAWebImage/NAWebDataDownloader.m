//
//  NAWebDataDownloader.m
//  NYWebImage
//
//  Created by zuopengl on 3/11/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "NAWebDataDownloader.h"
#import "NAWebDataDownloadOperation.h"


NSString *const NAWebImageErrorDomain = @"NAWebImageErrorDomain";


static NSString *const kWebDataOperationProgressKey  = @"kWebDataOperationProgressKey";
static NSString *const kWebDataOperationCompletedKey = @"kWebDataOperationCompletedKey";


@interface NAWebDataDownloader ()
@property (nonatomic, strong) Class operationClass;

@property (nonatomic, strong) NSOperationQueue *downloadQueue;
@property (weak, nonatomic) NSOperation *lastAddedOperation;

/**
 *  As follows:
 *  url: dictionary{progressBlockKey:value, completedBlockKey:value}
 */
@property (nonatomic, strong) NSMutableDictionary *urlCallbacks;
@property (nonatomic, strong) NSMutableDictionary *httpHeaderFields;

@property (nonatomic) dispatch_queue_t barrier_queue;
@end


@implementation NAWebDataDownloader

+ (NAWebDataDownloader *)sharedDownloader {
    static dispatch_once_t onceToken;
    static NAWebDataDownloader *inst;
    dispatch_once(&onceToken, ^{
        inst = [NAWebDataDownloader new];
    });
    return inst;
}


- (instancetype)init {
    if ((self = [super init])) {
        _downloadOrder = kNAWebDataDownloadOrderOfFIFO;
        _downloadTimeOut = 15.f;
        
        _operationClass = NSClassFromString(@"NAWebDataDownloadOperation");
        
        _downloadQueue = [NSOperationQueue new];
        _downloadQueue.maxConcurrentOperationCount = 6;
        
        _barrier_queue = dispatch_queue_create("downloader.queue.NAWebData", DISPATCH_QUEUE_CONCURRENT);
        
        _httpHeaderFields = [NSMutableDictionary new];
        
        _urlCallbacks = [NSMutableDictionary new];
    }
    return self;
}


- (void)dealloc {
    [_downloadQueue cancelAllOperations];
    safe_dispatch_release(_barrier_queue);
}


- (id<NAWebDataOperation>)downloadDataWithURL:(NSURL *)url progressBlock:(NAWebDataOperationProgressBlock)progressBlock completedBlock:(NAWebDataOperationCompletedBlock)completedBlock {
    return [self downloadDataWithURL:url options:kNAWebDataDownloadDefaultOption progressBlock:progressBlock completedBlock:completedBlock];
}


- (id<NAWebDataOperation>)downloadDataWithURL:(NSURL *)url options:(NAWebDataDownloadOptions)options progressBlock:(NAWebDataOperationProgressBlock)progressBlock completedBlock:(NAWebDataOperationCompletedBlock)completedBlock {
    if ([url isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)url];
    }
    
    if (!url || [url.absoluteString length] <= 0) {
        safe_block(completedBlock, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Request url is nil"}], YES);
        return nil;
    }
    
    if (![url isKindOfClass:[NSURL class]]) {
        safe_block(completedBlock, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Url is a valid type of NSURL"}], YES);
        return nil;
    }
    
    __block NAWebDataDownloadOperation *operation = nil;
    __weak typeof(self) weakSelf = self;
    [self setUrl:url progressBlock:progressBlock completedBlock:completedBlock createBlock:^{
        
        __weak typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return ;
        
        NSTimeInterval timeoutInterval = strongSelf.downloadTimeOut;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }
        
        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & kNAWebDataDownloadUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        request.HTTPShouldHandleCookies = (options & kNAWebDataDownloadHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        request.allHTTPHeaderFields = strongSelf.httpHeaderFields;

        operation = [[self.operationClass alloc] initWithRequest:request progressBlock:^(NSData *data, NSInteger receivedSize, NSInteger expectedSize) {
            
            __weak typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return ;
            
            __block NSArray *callbackForURL = nil;
            dispatch_sync(strongSelf2.barrier_queue, ^{
                callbackForURL = [strongSelf2.urlCallbacks[url] copy];
            });
            
            for (NSDictionary *callback in callbackForURL) {
                NAWebDataOperationProgressBlock dataProgressBlock = callback[kWebDataOperationProgressKey];
                safe_block(dataProgressBlock, data, receivedSize, expectedSize);
            }

        } completedBlock:^(NSData *data, NSError *error, BOOL finished) {
           
            __weak typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return ;
            
            __block NSArray *callbackForURL = nil;
            dispatch_sync(strongSelf2.barrier_queue, ^{
                callbackForURL = [strongSelf2.urlCallbacks[url] copy];
                if (finished) {
                    [strongSelf2.urlCallbacks removeObjectForKey:url];
                }
            });
            
            for (NSDictionary *callback in callbackForURL) {
                NAWebDataOperationCompletedBlock dataCompletedBlock = callback[kWebDataOperationCompletedKey];
                safe_block(dataCompletedBlock, data, error, finished);
            }

        } canceledBlock:^{
            
            __weak typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return ;
            
            [strongSelf2.urlCallbacks removeObjectForKey:url];
            
        }];
        
        // config operation property
        if (strongSelf.urlCredential) {
            operation.urlCredential = strongSelf.urlCredential;
        } else if (strongSelf.username && strongSelf.password) {
            operation.urlCredential = [NSURLCredential credentialWithUser:strongSelf.username password:strongSelf.password persistence:NSURLCredentialPersistenceForSession];
        }
        if (options & kNAWebDataDownloadHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        } else {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        }
        
        [strongSelf.downloadQueue addOperation:operation];
        if (strongSelf.downloadOrder == kNAWebDataDownloadrderOfLIFO) {
            [strongSelf.lastAddedOperation addDependency:operation];
            strongSelf.lastAddedOperation = operation;
        }
    }];
    
    return operation;
}


- (id<NAWebDataOperation>)downloadImageWithURL:(NSURL *)url options:(NAWebDataDownloadOptions)options progressBlock:(NAWebImageOperationProgressBlock)progressBlock completedBlock:(NAWebImageOperationCompletedBlock)completedBlock {
    if ([url isKindOfClass:[NSString class]]) {
        url = [NSURL URLWithString:(NSString *)url];
    }
    
    if (!url || [url.absoluteString length] <= 0) {
        safe_block(completedBlock, nil, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Request url is nil"}], YES);
        return nil;
    }
    
    
    if (![url isKindOfClass:[NSURL class]]) {
        safe_block(completedBlock, nil, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"url is a valid type of NSURL"}], YES);
        return nil;
    }
    
    __weak typeof(self) weakSelf = self;
    __block NAWebDataDownloadOperation *operation = nil;
    [self setUrl:url progressBlock:^(NSData *data, NSInteger receivedSize, NSInteger expectedSize) {
        
        if (data.length > 0 && completedBlock) {
            CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            NSInteger width = 0, height = 0;
            NSInteger orientation = 0;
            if (width + height == 0) {
                CFDictionaryRef properties =  CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
                
                CFTypeRef value = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
                if (value) CFNumberGetValue(value, kCFNumberLongType, &width);
                
                value = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
                if (value) CFNumberGetValue(value, kCFNumberLongType, &height);
                
                value = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
                if (value) CFNumberGetValue(value, kCFNumberNSIntegerType, &orientation);
                
                CFRelease(properties);
                
//                orientation = [[self class] orientationFromPropertyValue:(orientation == -1 ? 1 : orientation)];
            }
            
            if (width + height > 0 && receivedSize < expectedSize) {
                CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
                if (partialImageRef) {
                    UIImage *tmpImage = partialImageRef ? [UIImage imageWithCGImage:partialImageRef] : nil;
                    
                    safe_async_main_queue_block(completedBlock, tmpImage, data, nil, NO);
                    
                    CGImageRelease(partialImageRef);
                }
            }
            
            CFRelease(imageSource);
        }
        safe_block(progressBlock, receivedSize, expectedSize);
        
    } completedBlock:^(NSData *data, NSError *error, BOOL finished) {
        
        if (!error) {
            if (data.length > 0) {
                UIImage *tmpImage = [UIImage imageWithData:data scale:1.f];
                if (tmpImage) {
                    if (CGSizeEqualToSize(tmpImage.size, CGSizeZero)) {
                        safe_block(completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image has 0 pixels"}], finished);
                    } else {
                        safe_block(completedBlock, tmpImage, data, nil, finished);
                    }
                } else {
                    safe_block(completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded Data is not image"}], finished);
                }
            } else {
                safe_block(completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}], finished);
            }
        } else {
            safe_block(completedBlock, nil, nil, error, finished);
        }
        
    } createBlock:^{
       
        // first execution to create operation
        __weak typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return ;
        
        NSTimeInterval timeoutInterval = strongSelf.downloadTimeOut;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }
        
        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & kNAWebDataDownloadUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        request.HTTPShouldHandleCookies = (options & kNAWebDataDownloadHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        NSMutableDictionary *httpHeaders = [strongSelf.httpHeaderFields mutableCopy];
        httpHeaders[@"Accept"] = @"image/*;q=0.8";
        request.allHTTPHeaderFields = httpHeaders;
        
        operation = [[self.operationClass alloc] initWithRequest:request progressBlock:^(NSData *data, NSInteger receivedSize, NSInteger expectedSize) {
            
            __weak typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return ;
            
            __block NSArray *callbackForURL = nil;
            dispatch_sync(strongSelf2.barrier_queue, ^{
                callbackForURL = [strongSelf2.urlCallbacks[url] copy];
            });
            
            for (NSDictionary *callback in callbackForURL) {
                NAWebDataOperationProgressBlock dataProgressBlock = callback[kWebDataOperationProgressKey];
                safe_block(dataProgressBlock, data, receivedSize, expectedSize);
            }
            
        } completedBlock:^(NSData *data, NSError *error, BOOL finished) {
            
            __weak typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return ;
            
            __block NSArray *callbackForURL = nil;
            dispatch_sync(strongSelf2.barrier_queue, ^{
                callbackForURL = [strongSelf2.urlCallbacks[url] copy];
                if (finished) {
                    [strongSelf2.urlCallbacks removeObjectForKey:url];
                }
            });
            
            for (NSDictionary *callback in callbackForURL) {
                NAWebDataOperationCompletedBlock dataCompletedBlock = callback[kWebDataOperationCompletedKey];
                safe_block(dataCompletedBlock, data, error, finished);
            }
            
        } canceledBlock:^{
            
            __weak typeof(weakSelf) strongSelf2 = weakSelf;
            if (!strongSelf2) return ;
            
            [strongSelf2.urlCallbacks removeObjectForKey:url];
            
        }];
        
        // config operation property
        if (strongSelf.urlCredential) {
            operation.urlCredential = strongSelf.urlCredential;
        } else if (strongSelf.username && strongSelf.password) {
            operation.urlCredential = [NSURLCredential credentialWithUser:strongSelf.username password:strongSelf.password persistence:NSURLCredentialPersistenceForSession];
        }
        if (options & kNAWebDataDownloadHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }
        
        [strongSelf.downloadQueue addOperation:operation];
        if (strongSelf.downloadOrder == kNAWebDataDownloadrderOfLIFO) {
            [strongSelf.lastAddedOperation addDependency:operation];
            strongSelf.lastAddedOperation = operation;
        }
    }];
 
    return operation;
}


- (void)setUrl:(NSURL *)url progressBlock:(NAWebDataOperationProgressBlock)progressBlock completedBlock:(NAWebDataOperationCompletedBlock)completedBlock createBlock:(NAWebDataNoParamsBlock)createBlock {
    dispatch_barrier_sync(_barrier_queue, ^{
        BOOL isFirst; // if firstly request the url
        if (!self.urlCallbacks[url]) {
            isFirst = YES;
            self.urlCallbacks[url] = [NSMutableArray new];
        }
        
        NSMutableArray *callbackForURL = self.urlCallbacks[url];
        NSMutableDictionary *callbacks = [NSMutableDictionary new];
        if (completedBlock) {
            callbacks[kWebDataOperationCompletedKey] = [completedBlock copy];
        }
        if (progressBlock) {
            callbacks[kWebDataOperationProgressKey] = [progressBlock copy];
        }
        [callbackForURL addObject:callbacks];
        self.urlCallbacks[url] = callbackForURL;
        
        if (isFirst) { // only to request when first to load url
            safe_block(createBlock);
        }
    });
}


- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if ([value length] > 0 && [field length] > 0) {
        self.httpHeaderFields[field] = value;
    }
}


- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    return self.httpHeaderFields[field];
}


- (void)setOperationClass:(Class)aClass {
    self.operationClass = aClass;
}


- (NSInteger)countOfCurrentDownloads {
    return [self.downloadQueue operationCount];
}


- (NSInteger)countOfMaxConcurrentDownloads {
    return [self.downloadQueue maxConcurrentOperationCount];
}


- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    if (self.downloadQueue.operationCount != maxConcurrentDownloads) {
        self.downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
    }
}


- (void)setSuspended:(BOOL)suspended {
    [self.downloadQueue setSuspended:suspended];
}

@end

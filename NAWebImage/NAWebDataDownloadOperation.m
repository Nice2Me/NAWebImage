//
//  NAWebDataDownloadOperation.m
//  NYWebData
//
//  Created by zuopengl on 3/9/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "NAWebDataDownloadOperation.h"


#pragma mark - Notifications Name

NSString *const NAWebDataDownloadStartNotification           = @"NAWebDataDownloadStartNotification";
NSString *const NAWebDataDownloadReceiveResponseNotification = @"NAWebDataDownloadReceiveResponseNotification";
NSString *const NAWebDataDownloadStopNotification            = @"NAWebDataDownloadStopNotification";
NSString *const NAWebDataDownloadFinishNotification          = @"NAWebDataDownloadFinishNotification";


NSString *const NAWebDataErrorDomain = @"NAWebDataErrorDomain";


#pragma mark - Extension for NAWebImageDownloaderOperation

@interface NAWebDataDownloadOperation ()
<
NSURLConnectionDelegate,
NSURLConnectionDataDelegate
>

@property (nonatomic, assign, getter=isResponseFromCache) BOOL responseFromCache;
@property (nonatomic, assign, getter=isSupportedContinueFromBreakpoint) BOOL supportedContinueFromBreakpoint;

@property (nonatomic, assign, getter=isFinished) BOOL finished;
@property (nonatomic, assign, getter=isExecuting) BOOL executing;

@property (nonatomic, strong) NSURLRequest *urlRequest;
@property (nonatomic, strong) NSURLResponse *urlResponse;

// NSURLConnection
@property (nonatomic, strong) NSURLConnection *urlConnection;

// NSURLSession
@property (nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (nonatomic, strong) NSOperationQueue *urlSessionQueue;
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) NSURLSessionTask *urlSessionTask;

@property (nonatomic, copy) NAWebDataOperationProgressBlock  progressBlock;
@property (nonatomic, copy) NAWebDataOperationCompletedBlock completedBlock;
@property (nonatomic, copy) NAWebDataOperationCancelBlock    canceledBlock;

@property (nonatomic, assign) NSInteger expectedSize;
@property (nonatomic, strong) NSMutableData *data;

// record current thread
@property (nonatomic, strong) NSThread *thread;

- (void)reset;
- (void)done;
- (void)cancelInternal;
- (void)cancelInternalAndStop;
+ (UIImageOrientation)orientationFromPropertyValue:(NSInteger)value;
@end


#pragma mark - Category NSURLConnection for NAWebImageDownloaderOperation
/**
 *  Category NSURLConnection for NAWebImageDownloaderOperation
 */
@interface NAWebDataDownloadOperation (NSURLConnection)
<
NSURLConnectionDelegate,
NSURLSessionDataDelegate
>
@end

@implementation NAWebDataDownloadOperation (NSURLConnection)

#pragma mark - NSURLConnectionDelegate and NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    self.data ? nil : (self.data = [NSMutableData new]);
    [self.data appendData:data];
    
    safe_block(self.progressBlock, self.data, self.data.length, self.expectedSize);
    
//    self.imageData ? nil : (self.imageData = [NSMutableData new]);
//    [self.imageData appendData:data];
//    
//    if ([self.imageData length] > 0 && self.completedBlock) {
//        const NSInteger receivedTotalSize = [self.imageData length];
//        
//        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self.imageData, NULL);
//        NSInteger width = 0, height = 0;
//        NSInteger orientation = 0;
//        if (width + height == 0) {
//            CFDictionaryRef properties =  CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
//            
//            CFTypeRef value = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
//            if (value) CFNumberGetValue(value, kCFNumberLongType, &width);
//            
//            value = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
//            if (value) CFNumberGetValue(value, kCFNumberLongType, &height);
//            
//            value = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
//            if (value) CFNumberGetValue(value, kCFNumberNSIntegerType, &orientation);
//            
//            CFRelease(properties);
//            
//            orientation = [[self class] orientationFromPropertyValue:(orientation == -1 ? 1 : orientation)];
//        }
//        
//        if (width + height > 0 && receivedTotalSize < self.expectedSize) {
//            CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
//            if (partialImageRef) {
//                UIImage *tmpImage = partialImageRef ? [UIImage imageWithCGImage:partialImageRef] : nil;
//                
//                safe_main_queue_block(self.completedBlock, tmpImage, self.imageData, nil, NO);
//                
//                CGImageRelease(partialImageRef);
//            }
//        }
//        
//        CFRelease(imageSource);
//    }
//    safe_block(self.progressBlock, [self.imageData length], self.expectedSize);
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    //'304 Not Modified' is an exceptional one
    if (![response respondsToSelector:@selector(statusCode)] || ([((NSHTTPURLResponse *)response) statusCode] < 400 && [((NSHTTPURLResponse *)response) statusCode] != 304)) {
        NSInteger expected = response.expectedContentLength > 0 ? (NSInteger)response.expectedContentLength : 0;
        self.data = [[NSMutableData alloc] initWithCapacity:expected];
        self.expectedSize = expected;
        
        safe_block(self.progressBlock, self.data, self.data.length, self.expectedSize);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadReceiveResponseNotification object:self];
        });
    } else {
        NSUInteger code = [((NSHTTPURLResponse *)response) statusCode];
        
        //This is the case when server returns '304 Not Modified'. It means that remote image is not changed.
        //In case of 304 we need just cancel the operation and return cached image from the cache.
        if (code == 304) {
            [self cancelInternal];
        } else {
            [self.urlConnection cancel];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadStopNotification object:nil];
        });
        
        safe_block(self.completedBlock, nil, [NSError errorWithDomain:NSURLErrorDomain code:[((NSHTTPURLResponse *)response) statusCode] userInfo:nil], YES);
        
        CFRunLoopStop(CFRunLoopGetCurrent());
        [self done];
    }
    
//    if (![response respondsToSelector:@selector(statusCode)] || ([((NSHTTPURLResponse *)response) statusCode] < 400 && [((NSHTTPURLResponse *)response) statusCode] != 304)) {
//        NSInteger expected = response.expectedContentLength > 0 ? (NSInteger)response.expectedContentLength : 0;
//        self.imageData = [[NSMutableData alloc] initWithCapacity:expected];
//        self.expectedSize = expected;
//        
//        safe_block(self.progressBlock, 0, self.expectedSize);
//        
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebImageDownloadReceiveResponseNotification object:self];
//        });
//    } else {
//        NSUInteger code = [((NSHTTPURLResponse *)response) statusCode];
//        
//        //This is the case when server returns '304 Not Modified'. It means that remote image is not changed.
//        //In case of 304 we need just cancel the operation and return cached image from the cache.
//        if (code == 304) {
//            [self cancelInternal];
//        } else {
//            [self.urlConnection cancel];
//        }
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebImageDownloadStopNotification object:self];
//        });
//        
//        safe_block(self.completedBlock, nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:[((NSHTTPURLResponse *)response) statusCode] userInfo:nil], YES);
//        
//        CFRunLoopStop(CFRunLoopGetCurrent());
//        [self done];
//    }
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (self.isFinished) return;
    
    @synchronized(self) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        
        self.thread = nil;
        self.urlConnection = nil;
        
        self.executing = NO;
        self.finished = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadStopNotification object:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadFinishNotification object:nil];
        });
    }
    
    if ([self.data length] > 0) {
        safe_block(self.completedBlock, self.data, nil, YES);
    } else {
        safe_block(self.completedBlock, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Image data is nil"}], YES);
    }
    [self done];
    
    
//    if (self.imageData) {
//        UIImage *image = [UIImage imageWithData:self.imageData scale:1.f];
//        
//        if (CGSizeEqualToSize(image.size, CGSizeZero)) {
//            safe_block(self.completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image has 0 pixels"}], YES);
//        } else {
//            safe_block(self.completedBlock, image, self.imageData, nil, YES);
//        }
//    } else {
//        safe_block(self.completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Image data is nil"}], YES);
//    }
//    
//    [self done];
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    @synchronized(self) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        
        self.thread = nil;
        self.urlConnection = nil;
        
        self.executing = NO;
        self.finished = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadStopNotification object:nil];
        });
        
        safe_block(self.completedBlock, nil, error, YES);
        
        [self done];
    };
}


- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    self.responseFromCache = NO; // If this method is called, it means the response wasn't read from cache
    if (self.urlRequest.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData) {
        // Prevents caching of responses
        return nil;
    } else {
        return cachedResponse;
    }
}

@end



#pragma mark - Category NSURLSession for NAWebDataDownloadOperation
/**
 *  Category NSURLSession for NAWebDataDownloadOperation
 */
@interface NAWebDataDownloadOperation (NSURLSession)
<
NSURLSessionDelegate,
NSURLSessionDataDelegate
>
@end

@implementation NAWebDataDownloadOperation (NSURLSession)

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @synchronized(self) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        
        self.thread = nil;
        self.urlSessionTask = nil;
        
        self.executing = NO;
        self.finished = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadStopNotification object:nil];
            if (!error) {
                [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadFinishNotification object:nil];
            }
        });
    }
    
    if (error) {
        safe_block(self.completedBlock, nil, error, YES);
    } else {
        if ([self.data length] > 0) {
            safe_block(self.completedBlock, self.data, nil, YES);
        } else {
            safe_block(self.completedBlock, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}], YES);
        }
    }
    
    self.completedBlock = nil;
    [self done];
    
//    if (error) {
//        safe_block(self.completedBlock, nil, nil, error, YES);
//    } else {
//        if (self.imageData) {
//            UIImage *tmpImage = [UIImage imageWithData:self.imageData scale:1.f];
//            if (tmpImage) {
//                if (CGSizeEqualToSize(tmpImage.size, CGSizeZero)) {
//                    safe_block(self.completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image has 0 pixels"}], YES);
//                } else {
//                    safe_block(self.completedBlock, tmpImage, self.imageData, nil, YES);
//                }
//            } else {
//                safe_block(self.completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Downloaded Data is not image"}], YES);
//            }
//        } else {
//            safe_block(self.completedBlock, nil, nil, [NSError errorWithDomain:NAWebImageErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}], YES);
//        }
//    }
//    
//    self.completedBlock = nil;
//    [self done];
}


- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    self.data ? nil : (self.data = [NSMutableData new]);
    [self.data appendData:data];
    self.expectedSize = dataTask.countOfBytesExpectedToReceive;
    
    safe_block(self.progressBlock, self.data, self.data.length, self.expectedSize);

    
//    self.imageData ? nil : (self.imageData = [NSMutableData new]);
//    [self.imageData appendData:data];
//    self.expectedSize = dataTask.countOfBytesExpectedToReceive;
//    
//    if ([self.imageData length] > 0 && self.completedBlock) {
//        const NSInteger receivedTotalSize = [self.imageData length];
//        
//        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self.imageData, NULL);
//        NSInteger width = 0, height = 0;
//        NSInteger orientation = 0;
//        if (width + height == 0) {
//            CFDictionaryRef properties =  CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
//            
//            CFTypeRef value = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
//            if (value) CFNumberGetValue(value, kCFNumberLongType, &width);
//            
//            value = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
//            if (value) CFNumberGetValue(value, kCFNumberLongType, &height);
//            
//            value = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
//            if (value) CFNumberGetValue(value, kCFNumberNSIntegerType, &orientation);
//            
//            CFRelease(properties);
//            
//            orientation = [[self class] orientationFromPropertyValue:(orientation == -1 ? 1 : orientation)];
//        }
//        
//        if (width + height > 0 && receivedTotalSize < self.expectedSize) {
//            CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
//            if (partialImageRef) {
//                UIImage *tmpImage = partialImageRef ? [UIImage imageWithCGImage:partialImageRef] : nil;
//                
//                safe_main_queue_block(self.completedBlock, tmpImage, self.imageData, nil, NO);
//                
//                CGImageRelease(partialImageRef);
//            }
//        }
//        
//        CFRelease(imageSource);
//    }
//    
//    safe_block(self.progressBlock, [self.imageData length], self.expectedSize);
}


- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    @synchronized(self) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        self.executing = NO;
        self.finished = YES;
    }
    
    safe_block(self.completedBlock, nil, [NSError errorWithDomain:NAWebDataErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: @"Session become invalid"}], YES);
    
    self.completedBlock = nil;
    [self done];
}


- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse * _Nullable))completionHandler {
    
}

@end



/**
 *  Implementation of NAWebDataDownloadOperation
 */
@implementation NAWebDataDownloadOperation

@synthesize finished = _finished;
@synthesize executing = _executing;


- (instancetype)init {
    @throw @"Please use initWithRequest:progressBlock:completionBlock:cancelBlock";
}


- (instancetype)initWithRequest:(NSURLRequest *)request
                  progressBlock:(NAWebDataOperationProgressBlock)progressBlock
                completedBlock:(NAWebDataOperationCompletedBlock)completedBlock
                    canceledBlock:(NAWebDataOperationCancelBlock)canceledBlock {
    if ((self = [super init])) {
        _responseFromCache = NO;
        _sessionTask = NO;
        
        _urlRequest = request;
        
        _progressBlock = progressBlock;
        _completedBlock = completedBlock;
        _canceledBlock = canceledBlock;
        
        _data = nil;
        _expectedSize = NSURLResponseUnknownLength;
        
        _sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        _urlSessionQueue = [[NSOperationQueue alloc] init];
        _urlSessionQueue.name = @"NAWebData.urlSessionQueue";
    }
    return self;
}


- (void)start {
    if (!_urlRequest) {
        return;
    }
    
    @synchronized(self) {
        if (self.isCancelled) {
            self.finished = YES;
            [self reset];
            return;
        }
    }
    
    if ([self isSessionTask]) {
        if (!self.sessionConfiguration) {
            self.sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
        }
        if (!self.urlSession) {
            self.urlSession = [NSURLSession sessionWithConfiguration:self.sessionConfiguration delegate:self delegateQueue:self.urlSessionQueue];
        }
        self.urlSessionTask = [self.urlSession dataTaskWithRequest:self.urlRequest];
        [self.urlSessionTask resume];
    } else {
        self.urlConnection = [[NSURLConnection alloc] initWithRequest:_urlRequest delegate:self startImmediately:NO];
        self.executing = YES;
        self.thread = [NSThread currentThread];
        
        [self.urlConnection start];

        safe_async_main_queue_block(self.progressBlock, nil, 0, NSURLResponseUnknownLength);
        
        if (self.urlConnection) {
            safe_async_main_queue_block(^() {
                [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadStartNotification object:self];
            });

            if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_5_1) {
                // Make sure to run the runloop in our background thread so it can process downloaded data
                // Note: we use a timeout to work around an issue with NSURLConnection cancel under iOS 5
                //       not waking up the runloop, leading to dead threads (see https://github.com/rs/SDWebImage/issues/466)
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, false);
            } else {
                CFRunLoopRun();
            }
        } else {
            safe_block(self.completedBlock, nil, [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Connection can't be initialized"}], YES);
        }
    }
}


#pragma mark - utility

- (void)reset {
    _urlRequest = nil;
    _urlResponse = nil;
    _urlConnection = nil;
    
    _urlSession = nil;
    _urlSessionTask = nil;
    
    _progressBlock = nil;
    _completedBlock = nil;
    _canceledBlock = nil;
    
    _thread = nil;
    
    _data = nil;
}


- (void)cancel {
    @synchronized(self) {
        if (self.thread) {
            [self performSelector:@selector(cancelInternalAndStop) onThread:self.thread withObject:nil waitUntilDone:NO];
        } else {
            [self cancelInternal];
        }
    };
}


- (BOOL)isConcurrent {
    return YES;
}


/**
 *  called when received all data (included fail and success ...)
 */
- (void)done {
    self.executing = NO;
    self.finished = YES;
    
    [self reset];
}


#pragma mark - private method

/**
 *  cancel and stop current runloop
 */
- (void)cancelInternalAndStop {
    if (self.finished) return;
    [self cancelInternal];
    CFRunLoopStop(CFRunLoopGetCurrent());
}


- (void)cancelInternal {
    if (self.finished) return;
    
    [super cancel];
    
    safe_block(_canceledBlock);
    
    if (self.urlConnection) {
        [self.urlConnection cancel];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NAWebDataDownloadStopNotification object:nil];
        });
        
        if (self.executing) self.executing = NO;
        if (!self.finished) self.finished = YES;
    }
    
    [self reset];
}


+ (UIImageOrientation)orientationFromPropertyValue:(NSInteger)value {
    switch (value) {
        case 1:
            return UIImageOrientationUp;
        case 3:
            return UIImageOrientationDown;
        case 8:
            return UIImageOrientationLeft;
        case 6:
            return UIImageOrientationRight;
        case 2:
            return UIImageOrientationUpMirrored;
        case 4:
            return UIImageOrientationDownMirrored;
        case 5:
            return UIImageOrientationLeftMirrored;
        case 7:
            return UIImageOrientationRightMirrored;
        default:
            return UIImageOrientationUp;
    }
}


#pragma mark - property

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"_isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"_isFinished"];
}


- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"_isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"_isExecuting"];
}


- (void)setSessionTask:(BOOL)isSessionTask {
    _sessionTask = (isSessionTask && IS_IOS7_LATER);
}

@end

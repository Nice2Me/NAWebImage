//
//  NAImageCache.m
//  NAWebImage
//
//  Created by zuopengl on 3/11/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "NAImageCache.h"
#import "NAWebDataDef.h"



inline NSUInteger NACacheCostForImage(UIImage *image) {
    return (image.size.width * image.size.height * image.scale);
}

inline NSString* NACacheKeyForURL(NSURL *url) {
    return (url ? [NSString stringWithString:url.absoluteString] : nil);
}

inline UIImage* NAScaledImageForKey(NSString *key, UIImage *image) {
    if (!key || !image) {
        return image;
    }
    
    if ([image.images count] > 0) {
        NSMutableArray *newImages = [NSMutableArray arrayWithCapacity:[image.images count]];
        for (int i = 0; i < [image.images count]; i++) {
            [newImages addObject:NAScaledImageForKey(key, image.images[i])];
        }
        
        return [UIImage animatedImageWithImages:newImages duration:image.duration];
    } else {
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
            CGFloat scale = [UIScreen mainScreen].scale;
            if (key.length >= 8) {
                NSRange scaleRange = [key rangeOfString:@"@2x."];
                if (scaleRange.length != NSNotFound) {
                    scale = 2.f;
                }
                
                scaleRange = [key rangeOfString:@"@3x."];
                if (scaleRange.length != NSNotFound) {
                    scale = 3.f;
                }
            }
            
            return [UIImage imageWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
        }
        return image;
    }
}


static NSUInteger kDefaultMaxCacheAge = 60 * 60 * 24 * 7;
static unsigned char kPNGSignatureBytes[8] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
static NSData *kPngSignatureData = nil;

inline BOOL HasPNGPrefixForImageData(NSData *data) {
    if (data.length >= kPngSignatureData.length) {
        return [[data subdataWithRange:NSMakeRange(0, kPngSignatureData.length)] isEqualToData:kPngSignatureData];
    }
    return NO;
}


/**
 * Automatic recycle cache policy
 */
@interface NAAutoPurgeCache : NSCache
@end

@implementation NAAutoPurgeCache
- (instancetype)init {
    if ((self = [super init])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}


- (void)setObject:(id)obj forKey:(id)key {
    if ([obj isKindOfClass:UIImage.class]) {
        [super setObject:obj forKey:key cost:NACacheCostForImage((UIImage *)obj)];
    } else {
        [super setObject:obj forKey:key];
    }
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}
@end



// Stored path is followed: ***/cacheDirectory/fileName
@interface NAImageCache ()
@property (nonatomic, strong) NSCache *memCache;
@property (nonatomic, copy) NSString *diskCachePath;

@property (nonatomic, strong) dispatch_queue_t ioQueue;

@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation NAImageCache

+ (instancetype)sharedImageCache {
    static dispatch_once_t onceToken;
    static NAImageCache *inst;
    dispatch_once(&onceToken, ^{
        inst = [self new];
    });
    return inst;
}


+ (NSString *)getImageCacheDirectoryForNamespace:(NSString *)namespace {
    namespace = (namespace ? : @"default");
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:namespace];
}

   
- (instancetype)init {
    return [self initWithNamespace:@"default"];
}


- (instancetype)initWithNamespace:(NSString *)namespace {
    return [self initWithNamespace:namespace cacheDirectory:[self.class getImageCacheDirectoryForNamespace:namespace]];
}


- (instancetype)initWithNamespace:(NSString *)namespace cacheDirectory:(NSString *)cacheDirectory {
    if ((self = [super init])) {
        kPngSignatureData = [NSData dataWithBytes:kPNGSignatureBytes length:8];
        
        NSString *fullNamespace = [@"namespace.memoryCache.directory." stringByAppendingString:namespace];
        if (cacheDirectory) {
            self.diskCachePath = cacheDirectory;
        } else {
            self.diskCachePath = [self.class getImageCacheDirectoryForNamespace:namespace];
        }
        
        _memCache = [[NAAutoPurgeCache alloc] init];
        _memCache.name = fullNamespace;
        _memCache.countLimit = 30;
        _memCache.totalCostLimit = 50;
      
        _maxCacheAge = kDefaultMaxCacheAge;
        _maxCacheSize = 50;
        
        _ioQueue = dispatch_queue_create("na.imageCache.NAWebData", DISPATCH_QUEUE_SERIAL);
        dispatch_sync(_ioQueue, ^{
            _fileManager = [NSFileManager new];
        });
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearMemory) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cleanDisk) name:UIApplicationWillTerminateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cleanDiskOnBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;

}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    safe_dispatch_release(self.ioQueue);
}


- (void)storeImage:(UIImage *)image toDisk:(BOOL)disked forKey:(NSString *)key {
    if (!image || !key) {
        return;
    }
    
    if (self.synchronizeImageInMemory) {
        [self.memCache setObject:image forKey:key];
    }
    if (disked) {
        dispatch_async(self.ioQueue, ^{
            [self writeImage:image forKey:key toPath:self.diskCachePath];
        });
    }
}


- (void)storeImage:(UIImage *)image forKey:(NSString *)key {
    [self storeImage:image toDisk:NO forKey:key];
}


- (NSOperation *)queryImageForKey:(NSString *)key completion:(NAImageQueryCompletionBlock)completion {
    if (!completion) {
        return nil;
    }
    
    if (key.length <= 0) {
        safe_block(completion, nil, kNAImageCacheNone);
        return nil;
    }
    
    UIImage *image = [self imageFromMemoryCacheForKey:key];
    if (image) {
        safe_block(completion, image, kNAImageCacheMemory);
        return nil;
    }
    
    NSOperation *operation = [NSOperation new];
    dispatch_async(self.ioQueue, ^{
        if ([operation isCancelled]) {
            safe_block(completion, nil, kNAImageCacheNone);
            return;
        }
        @autoreleasepool {
            UIImage *diskImage = [self findDiskImageBySearchingAllPathsForKey:key];
            
            safe_async_main_queue_block(completion, diskImage, kNAImageCacheDisk);
        }
    });
    return operation;
}


- (UIImage *)imageFromMemoryCacheForKey:(NSString *)key {
    if (key.length > 0) {
        return [self.memCache objectForKey:key];
    }
    return nil;
}



- (UIImage *)imageFromDiskCacheForKey:(NSString *)key {
    if (key.length <= 0) {
        return nil;
    }
    
    UIImage *image = [self imageFromMemoryCacheForKey:key];
    if (!image) {
        image = [self findDiskImageBySearchingAllPathsForKey:key];
        if (image && self.synchronizeImageInMemory) {
            [self.memCache setObject:image forKey:key];
        }
    }
    return image;
}


- (void)removeImageForKey:(NSString *)key {
    [self removeImageForKey:key andDisk:NO];
}


- (void)removeImageForKey:(NSString *)key andDisk:(BOOL)disked {
    return [self removeImageForKey:key andDisk:disked completion:nil];
}


- (void)removeImageForKey:(NSString *)key andDisk:(BOOL)disked completion:(NAImageRemoveCompletionBlock)completion {
    if (key.length <= 0) {
        return;
    }
    
    [self.memCache removeObjectForKey:key];
    
    if (disked) {
        dispatch_async(self.ioQueue, ^{
            [_fileManager removeItemAtPath:[self defaultFileFullPathForKey:key] error:nil];
            safe_async_main_queue_block(completion);
        });
    } else {
        safe_block(completion);
    }
}


- (BOOL)cacheImageExistsForKey:(NSString *)key {
    return ([self.memCache objectForKey:key] != nil);
}


- (BOOL)diskImageExistsForKey:(NSString *)key {
    BOOL existed = [_fileManager fileExistsAtPath:[self defaultFileFullPathForKey:key]];
    if (!existed) {
       existed = [_fileManager fileExistsAtPath:[[self defaultFileFullPathForKey:key] stringByDeletingPathExtension]];
    }
    return existed;
}


- (void)diskImageExistsForKey:(NSString *)key completion:(NAImageCheckCompletionBlock)completion {
    dispatch_async(self.ioQueue, ^{
        BOOL existed = [_fileManager fileExistsAtPath:[self defaultFileFullPathForKey:key]];
        if (!existed) {
            existed = [_fileManager fileExistsAtPath:[[self defaultFileFullPathForKey:key] stringByDeletingPathExtension]];
        }
        safe_async_main_queue_block(completion, existed);
    });
}


- (void)clearMemory {
    [self.memCache removeAllObjects];
}

/**
 *  清理所有的磁盘缓存
 */
- (void)clearDisk {
    [self clearDiskWithCompletion:nil];
}


/**
 *  仅仅清理过期的磁盘文件缓存
 */
- (void)clearDiskWithCompletion:(NANoParamsBlock)completion {
    dispatch_async(self.ioQueue, ^{
        [_fileManager removeItemAtPath:self.diskCachePath error:nil];
        [_fileManager createDirectoryAtPath:self.diskCachePath withIntermediateDirectories:YES attributes:nil error:nil];
        safe_async_main_queue_block(completion);
    });
}


- (void)cleanDisk {
    [self cleanDiskWithCompletion:nil];
}


- (void)cleanDiskWithCompletion:(NANoParamsBlock)completion {
    dispatch_async(self.ioQueue, ^{
        NSArray *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];
        NSDirectoryEnumerator *dirEnum = [self.fileManager enumeratorAtURL:[NSURL fileURLWithPath:self.diskCachePath isDirectory:YES] includingPropertiesForKeys:resourceKeys options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];

        __block NSUInteger currentCacheSize = 0;
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.maxCacheAge];
        NSMutableArray *deletedUrls = [NSMutableArray new];
        NSMutableDictionary *cachedFiles = [NSMutableDictionary new];
        for (NSURL *fileUrl in dirEnum) {
            NSDictionary *resourceValues = [fileUrl resourceValuesForKeys:resourceKeys error:nil];
            
            // Skip directories.
            if ([resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }
            
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [deletedUrls addObject:fileUrl];
                continue;
            }
            
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += [totalAllocatedSize unsignedIntegerValue];
            [cachedFiles setObject:resourceValues forKey:fileUrl];
        }
        
        for (NSURL *deletedUrl in deletedUrls) {
            [self.fileManager removeItemAtURL:deletedUrl error:nil];
        }
        
        if (self.maxCacheSize > 0 && currentCacheSize > self.maxCacheSize) {
            NSUInteger desiredCacheSize = self.maxCacheSize / 2;
            // Sort the remaining cache files by their last modification time (oldest first).
            NSArray *sortedFiles = [cachedFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                            usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
                                                            }];
            
            // Delete files until we fall below our desired cache size.
            for (NSURL *fileUrl in sortedFiles) {
                if ([_fileManager removeItemAtURL:fileUrl error:nil]) {
                    NSDictionary *resourceValues = cachedFiles[fileUrl];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= [totalAllocatedSize unsignedIntegerValue];
                    
                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }
        
        safe_async_main_queue_block(completion);
    });
}


- (void)cleanDiskOnBackground {
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if (!UIApplicationClass ||[UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    
    UIApplication *application = [UIApplication sharedApplication];
    __block UIBackgroundTaskIdentifier bgTaskId = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:bgTaskId];
        bgTaskId = UIBackgroundTaskInvalid;
    }];
    
    [self cleanDiskWithCompletion:^{
        [application endBackgroundTask:bgTaskId];
        bgTaskId = UIBackgroundTaskInvalid;
    }];
}


- (void)clear {
    [self clearMemory];
    [self clearDisk];
}


- (NSUInteger)getSize {
    __block NSUInteger fileSizes = 0;
    @synchronized(self) {
        NSDirectoryEnumerator *dirEnum = [self.fileManager enumeratorAtPath:self.diskCachePath];
        for (NSString *fileName in dirEnum) {
            NSString *filePath = [self defaultFileFullPathForKey:fileName];
            NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:filePath error:nil];
            fileSizes += [attributes fileSize];
        }
    }
    return fileSizes;
}


- (void)diskCacheSizeWithCompletion:(NADiskQuerySizeCompletionBlock)completion {
    NSUInteger size = [self getSize];
    if (completion) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            completion(size);
        });
    }
}

- (NSUInteger)getCount {
    @synchronized(self) {
        NSDirectoryEnumerator *dirEnum = [self.fileManager enumeratorAtPath:self.diskCachePath];
        return [[dirEnum allObjects] count];
    }
}


#pragma mark - property

- (void)setTotalMemoryCostLimit:(NSUInteger)totalMemoryCostLimit {
    self.memCache.totalCostLimit = totalMemoryCostLimit;
}


- (void)setCountMemoryLimit:(NSUInteger)countMemoryLimit {
    self.memCache.countLimit = countMemoryLimit;
}

- (NSUInteger)totalMemoryCostLimit {
    return self.memCache.totalCostLimit;
}


- (NSUInteger)countMemoryLimit {
    return self.memCache.countLimit;
}


- (void)setMaxCacheAge:(NSUInteger)maxCacheAge {
    _maxCacheAge = maxCacheAge;
}


- (void)setMaxCacheSize:(NSUInteger)maxCacheSize {
    _maxCacheSize = maxCacheSize;
}


#pragma mark - private method

- (void)writeImage:(UIImage *)image forKey:(NSString *)key toPath:(NSString *)path {
    if (!image || key.length <= 0) {
        return;
    }
    path = path ? : self.diskCachePath;
   

    int alphaInfo = CGImageGetAlphaInfo(image.CGImage);
    BOOL hasAlpha = !(alphaInfo == kCGImageAlphaNone ||
                      alphaInfo == kCGImageAlphaNoneSkipFirst ||
                      alphaInfo == kCGImageAlphaNoneSkipLast);
    BOOL imageIsPng = hasAlpha;
    
    NSData *imageData = nil;
    if (imageIsPng) {
        imageData = UIImagePNGRepresentation(image);
    } else {
        imageData = UIImageJPEGRepresentation(image, 1.f);
    }
    
    NSString *fileFullPath = [path stringByAppendingPathComponent:key];
    [imageData writeToFile:fileFullPath atomically:YES];
}


- (UIImage *)findDiskImageBySearchingAllPathsForKey:(NSString *)key {
    if ([key length] <= 0) {
        return nil;
    }

    NSString *imageFullPath = [self defaultFileFullPathForKey:key];
    NSData *imageData = [NSData dataWithContentsOfFile:imageFullPath];
    UIImage *image = (imageData.length > 0) ? [UIImage imageWithData:imageData] : nil;
    if (image && self.synchronizeImageInMemory && ![self.memCache objectForKey:key]) {
        [self.memCache setObject:image forKey:key];
    }
    
    return image;
}


- (NSString *)defaultFileFullPathForKey:(NSString *)key {
    return [self fileFullPathForKey:key inPath:self.diskCachePath];
}


- (NSString *)fileFullPathForKey:(NSString *)key inPath:(NSString *)path {
    if (key.length <= 0) {
        return nil;
    }
    if (!path)  path = self.diskCachePath;
    NSString *fileName = [self fileNameForKey:key];
    return [path stringByAppendingPathComponent:fileName];
}


- (NSString *)fileNameForKey:(NSString *)key {
    const char *str = [key UTF8String];
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15], [[key pathExtension] isEqualToString:@""] ? @"" : [NSString stringWithFormat:@".%@", [key pathExtension]]];
    
    return filename;
}

@end

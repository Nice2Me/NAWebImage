//
//  NAImageCache.h
//  NAWebImage
//
//  Created by zuopengl on 3/11/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NAWebDataDef.h"


/**
 * Inline method
 */
extern NSUInteger NACacheCostForImage(UIImage *image);
extern NSString*  NACacheKeyForURL(NSURL *url);
extern UIImage*   NAScaledImageForKey(NSString *key, UIImage *image);


typedef NS_ENUM(NSUInteger, NAImageCacheType) {
    kNAImageCacheNone,
    kNAImageCacheMemory,
    kNAImageCacheDisk,
};

/**
 *  Block Declaration
 */
typedef void (^NAImageQueryCompletionBlock)(UIImage *image, NAImageCacheType cacheType);
typedef void (^NAImageCheckCompletionBlock)(BOOL existed);
typedef void (^NADiskQuerySizeCompletionBlock)(NSUInteger size);
typedef NAWebDataNoParamsBlock NANoParamsBlock;
typedef NAWebDataNoParamsBlock NAImageRemoveCompletionBlock;


@interface NAImageCache : NSObject

/**
 * If synchronize image between disk and memeory
 */
@property (nonatomic, assign) BOOL synchronizeImageInMemory;

// For mem cache
@property (nonatomic, assign) NSUInteger totalMemoryCostLimit;
@property (nonatomic, assign) NSUInteger countMemoryLimit;

// For disk cache
@property (assign, nonatomic) NSUInteger maxCacheAge;
@property (assign, nonatomic) NSUInteger maxCacheSize;


+ (instancetype)sharedImageCache;

- (void)storeImage:(UIImage *)image toDisk:(BOOL)disked forKey:(NSString *)key;
- (void)storeImage:(UIImage *)image forKey:(NSString *)key;

- (NSOperation *)queryImageForKey:(NSString *)key completion:(NAImageQueryCompletionBlock)completion;

// Query memory cache synchronously
- (UIImage *)imageFromMemoryCacheForKey:(NSString *)key;

// Query disk cache synchronously when check memory cache
- (UIImage *)imageFromDiskCacheForKey:(NSString *)key;

- (void)removeImageForKey:(NSString *)key;
- (void)removeImageForKey:(NSString *)key andDisk:(BOOL)disked;
- (void)removeImageForKey:(NSString *)key andDisk:(BOOL)disked completion:(NAImageRemoveCompletionBlock)completion;

- (BOOL)cacheImageExistsForKey:(NSString *)key;
- (BOOL)diskImageExistsForKey:(NSString *)key;
- (void)diskImageExistsForKey:(NSString *)key completion:(NAImageCheckCompletionBlock)completion;


- (void)clearMemory;
- (void)clearDisk;
- (void)clear;

@end


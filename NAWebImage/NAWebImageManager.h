//
//  NAWebImageManager.h
//  NAWebImage
//
//  Created by zuopengl on 3/14/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "NAWebDataDef.h"
#import "NAWebDataOperation.h"
#import "NAImageCache.h"

@class NAImageCache;
@class NAWebDataDownloader;

typedef NS_OPTIONS(NSUInteger, NAWebImageOptions) {
    /**
     * By default, when a URL fail to be downloaded, the URL is blacklisted so the library won't keep trying.
     * This flag disable this blacklisting.
     */
    NAWebImageRetryFailed = 1 << 0,
    
    /**
     * By default, image downloads are started during UI interactions, this flags disable this feature,
     * leading to delayed download on UIScrollView deceleration for instance.
     */
    NAWebImageLowPriority = 1 << 1,
    
    /**
     * This flag disables on-disk caching
     */
    NAWebImageCacheMemoryOnly = 1 << 2,
    
    /**
     * This flag enables progressive download, the image is displayed progressively during download as a browser would do.
     * By default, the image is only displayed once completely downloaded.
     */
    NAWebImageProgressiveDownload = 1 << 3,
    
    /**
     * Even if the image is cached, respect the HTTP response cache control, and refresh the image from remote location if needed.
     * The disk caching will be handled by NSURLCache instead of SDWebImage leading to slight performance degradation.
     * This option helps deal with images changing behind the same request URL, e.g. Facebook graph api profile pics.
     * If a cached image is refreshed, the completion block is called once with the cached image and again with the final image.
     *
     * Use this flag only if you can't make your URLs static with embedded cache busting parameter.
     */
    NAWebImageRefreshCached = 1 << 4,
    
    /**
     * In iOS 4+, continue the download of the image if the app goes to background. This is achieved by asking the system for
     * extra time in background to let the request finish. If the background task expires the operation will be cancelled.
     */
    NAWebImageContinueInBackground = 1 << 5,
    
    /**
     * Handles cookies stored in NSHTTPCookieStore by setting
     * NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     */
    NAWebImageHandleCookies = 1 << 6,
    
    /**
     * Enable to allow untrusted SSL certificates.
     * Useful for testing purposes. Use with caution in production.
     */
    NAWebImageAllowInvalidSSLCertificates = 1 << 7,
    
    /**
     * By default, image are loaded in the order they were queued. This flag move them to
     * the front of the queue and is loaded immediately instead of waiting for the current queue to be loaded (which
     * could take a while).
     */
    NAWebImageHighPriority = 1 << 8,
    
    /**
     * By default, placeholder images are loaded while the image is loading. This flag will delay the loading
     * of the placeholder image until after the image has finished loading.
     */
    NAWebImageDelayPlaceholder = 1 << 9,
    
    /**
     * We usually don't call transformDownloadedImage delegate method on animated images,
     * as most transformation code would mangle it.
     * Use this flag to transform them anyway.
     */
    NAWebImageTransformAnimatedImage = 1 << 10,
    
    /**
     * By default, image is added to the imageView after download. But in some cases, we want to
     * have the hand before setting the image (apply a filter or add it with cross-fade animation for instance)
     * Use this flag if you want to manually set the image in the completion when success
     */
    NAWebImageAvoidAutoSetImage = 1 << 11
};


@protocol NAWebImageOperation
<
NAWebDataOperation
>
@end

typedef void (^NAImageDownloadCompletedBlock)(UIImage *image, NSURL *imageUrl, NAImageCacheType cacheType, NSError *error, BOOL finished);
typedef NAWebImageOperationProgressBlock NAImageDownloadProgressBlock;
typedef NAWebDataNoParamsBlock NAImageDownloadCancelBlock;

@interface NAWebImageManager : NSObject

@property (nonatomic, strong, readonly) NAImageCache *imageCache;
@property (nonatomic, strong, readonly) NAWebDataDownloader *imageDownloader;

+ (instancetype)sharedManager;

- (id<NAWebImageOperation>)na_downloadImageForURL:(NSURL *)url options:(NAWebImageOptions)options progress:(NAImageDownloadProgressBlock)progressBlock completion:(NAImageDownloadCompletedBlock)completedBlock;

- (void)na_saveImageToCache:(UIImage *)image forURL:(NSURL *)url;
- (BOOL)na_cachedImageExistForURL:(NSURL *)url;
- (NSString *)na_cacheKeyForURL:(NSURL *)url;

- (void)cancelAll;
- (BOOL)isRunning;

@end

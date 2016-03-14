//
//  NAWebDataDownloader.h
//  NYWebImage
//
//  Created by zuopengl on 3/11/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NAWebDataDef.h"


/**
 *  Data download order
 */
typedef NS_ENUM(NSInteger, NAWebDataDownloadOrder) {
    /**
     *  first in first out
     */
    kNAWebDataDownloadOrderOfFIFO,
    /**
     *  last in first out
     */
    kNAWebDataDownloadrderOfLIFO,
};


/**
 *  Network data download options
 */
typedef NS_ENUM(NSInteger, NAWebDataDownloadOptions) {
    /**
     *  Put data download in low priority queue
     */
    kNAWebDataDownloadLowPriority                 = 1 << 0,
    /**
     *  Allow to gradual download
     */
    kNAWebDataDownloadProgressiveDownload         = 1 << 1,
    /**
     *  By default, request prevent NSURLCache. With this flag, request will use NSURLCache policy.
     */
    kNAWebDataDownloadUseNSURLCache               = 1 << 2,
    /**
     *  completedBlock call with image(nil) and imageData(nil) when image read from NSCache
     */
    kNAWebDataDownloadIgnoreCacheResponse         = 1 << 3,
    /**
     *  Allow to download data when app into background
     */
    kNAWebDataDownloadContinueInBackground        = 1 << 4,
    /**
     *  Handle cookie stored in NSHTTPCookieStore
     *  by setting NSMultableURLRequest.HTTPShouldHandleCookies = YES
     */
    kNAWebDataDownloadHandleCookies               = 1 << 5,
    /**
     * Enabled to dowload in untrusted SSL certificate
     */
    kNAWebDataDownloadAllowInvliadSSLCertificates = 1 << 6,
    /**
     *  Put data download in high priority queue
     */
    kNAWebDataDownloadHighPriority                = 1 << 7,
    /**
     *  default policy
     */
    kNAWebDataDownloadDefaultOption               = kNAWebDataDownloadLowPriority | kNAWebDataDownloadProgressiveDownload | kNAWebDataDownloadUseNSURLCache,
};


@interface NAWebDataDownloader : NSObject

@property (nonatomic, assign, readonly, getter=countOfCurrentDownloads) NSInteger currentDownloads;
@property (nonatomic, assign, getter=countOfMaxConcurrentDownloads) NSInteger maxConcurrentDownloads;
@property (nonatomic, assign) NSInteger downloadTimeOut;

// default is kNAWebDataDownloadOrderOfFIFO
@property (nonatomic, assign) NAWebDataDownloadOrder downloadOrder;

//
@property (nonatomic, strong) NSURLCredential *urlCredential;

@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;


+ (NAWebDataDownloader *)sharedDownloader;

/**
 *  download network data
 *
 *  @param url            request url
 *  @param progressBlock  load data progress callback
 *  @param completedBlock data response callback
 */
- (id<NAWebDataOperation>)downloadDataWithURL:(NSURL *)url options:(NAWebDataDownloadOptions)options progressBlock:(NAWebDataOperationProgressBlock)progressBlock completedBlock:(NAWebDataOperationCompletedBlock)completedBlock;

- (id<NAWebDataOperation>)downloadDataWithURL:(NSURL *)url progressBlock:(NAWebDataOperationProgressBlock)progressBlock completedBlock:(NAWebDataOperationCompletedBlock)completedBlock;

/**
 *  download network image
 *
 *  @param url            request url
 *  @param progressBlock  load data progress callback
 *  @param completedBlock data response callback
 */
- (id<NAWebDataOperation>)downloadImageWithURL:(NSURL *)url options:(NAWebDataDownloadOptions)options progressBlock:(NAWebImageOperationProgressBlock)progressBlock completedBlock:(NAWebImageOperationCompletedBlock)completedBlock;


- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field;
- (NSString *)valueForHTTPHeaderField:(NSString *)field;

- (void)setOperationClass:(Class)aClass;

- (void)setSuspended:(BOOL)suspended;

@end

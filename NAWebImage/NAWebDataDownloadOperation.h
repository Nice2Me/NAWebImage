//
//  NAWebDataDownloadOperation.h
//  NAWebImage
//
//  Created by zuopengl on 3/9/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NAWebDataDownloader.h"
#import "NAWebDataDef.h"

extern NSString *const NAWebDataDownloadStartNotification;
extern NSString *const NAWebDataDownloadReceiveResponseNotification;
extern NSString *const NAWebDataDownloadStopNotification;
extern NSString *const NAWebDataDownloadFinishNotification;



@interface NAWebDataDownloadOperation : NSOperation
<
NAWebDataOperation
>

@property (nonatomic, assign, getter=isSessionTask) BOOL sessionTask; // default is NSURLConnection, when version > 7.0 && sessionTask(YES) will use NSURLSession

@property (nonatomic, assign) NAWebDataDownloadOptions options;

@property (nonatomic, strong) NSURLCredential *urlCredential;

- (instancetype)initWithRequest:(NSURLRequest *)request
                  progressBlock:(NAWebDataOperationProgressBlock)progressBlock
                 completedBlock:(NAWebDataOperationCompletedBlock)completedBlock
                  canceledBlock:(NAWebDataOperationCancelBlock)canceledBlock;
@end

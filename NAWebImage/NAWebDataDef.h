//
//  NAWebImageDef.h
//  NYWebImage
//
//  Created by zuopengl on 3/9/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#ifndef NAWebDataDef_h
#define NAWebDataDef_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import "NAWebDataOperation.h"


// System Version
#define IS_IOS7_LATER ([[[UIDevice currentDevice] systemVersion] doubleValue] >= 7.0)


// Constant Macro
#define kNAWebImageDataSizeUnknown NSIntegerMax


//
extern NSString *const NAWebDataErrorDomain;
extern NSString *const NAWebImageErrorDomain;


// Safe Block
#define safe_block(block, ...) block ? block(__VA_ARGS__) : nil
#define safe_sync_queue_block(queue, block, ...) \
    do { \
        dispatch_sync(queue, ^ { \
                safe_block(block, __VA_ARGS__); \
        }); \
    } while (FALSE)
#define safe_sync_main_queue_block(block, ...) safe_sync_queue_block(dispatch_get_main_queue(), block, __VA_ARGS__)
#define safe_async_queue_block(queue, block, ...) \
    do { \
         dispatch_async(queue, ^ { \
                safe_block(block, __VA_ARGS__); \
        }); \
    } while (FALSE)
#define safe_async_main_queue_block(block, ...) safe_async_queue_block(dispatch_get_main_queue(), block, __VA_ARGS__)


#if OS_OBJECT_USE_OBJC
    #undef safe_dispatch_release
    #define safe_dispatch_release(obj)
#else
    #undef safe_dispatch_release
    #define safe_dispatch_release(obj) (dispatch_release(obj))
#endif



typedef void(^NAWebDataOperationProgressBlock)(NSData *data, NSInteger receivedSize, NSInteger expectedSize);
typedef void(^NAWebDataOperationCompletedBlock)(NSData *data, NSError *error, BOOL finished);

typedef void(^NAWebImageOperationProgressBlock)(NSInteger receivedSize, NSInteger expectedSize);
typedef void(^NAWebImageOperationCompletedBlock)(UIImage *image, NSData *data, NSError *error, BOOL finished);

typedef void(^NAWebDataNoParamsBlock)();
typedef NAWebDataNoParamsBlock NAWebDataOperationCancelBlock;
typedef NAWebDataNoParamsBlock NAWebImageOperationCancelBlock;

#endif /* NYWebImageDef_h */

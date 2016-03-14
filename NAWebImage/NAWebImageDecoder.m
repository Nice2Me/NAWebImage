//
//  NAWebImageDecoder.m
//  NAWebImage
//
//  Created by zuopengl on 3/14/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "NAWebImageDecoder.h"

@implementation UIImage (imageDecoder)

/**
 *  Generate new image with alpha
 *
 *  @param image original image
 *
 *  @return image with alpha
 */
+ (UIImage *)decodedImageWithImage:(UIImage *)image {
    if (!image || image.images) {
        return image;
    }
    
    CGImageRef imageRef = image.CGImage;
    CGImageAlphaInfo alphInfo =  CGImageGetAlphaInfo(imageRef);
    BOOL anyAlpha = (alphInfo == kCGImageAlphaFirst || alphInfo == kCGImageAlphaLast ||
                     alphInfo == kCGImageAlphaPremultipliedFirst ||
                     alphInfo == kCGImageAlphaPremultipliedLast);
    if (anyAlpha) {
        return image;
    }
    
    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpaceRef = CGImageGetColorSpace(imageRef);
    CGColorSpaceModel imageColorSpaceModel = CGColorSpaceGetModel(colorSpaceRef);
    
    bool unsupportedColorSpace = (imageColorSpaceModel == 0 || imageColorSpaceModel == -1 || imageColorSpaceModel == kCGColorSpaceModelCMYK || imageColorSpaceModel == kCGColorSpaceModelIndexed);
    if (unsupportedColorSpace)
        colorSpaceRef = CGColorSpaceCreateDeviceRGB();

    CGContextRef bitmapCxt = CGBitmapContextCreate(NULL, width, height, CGImageGetBitsPerComponent(imageRef), 0, colorSpaceRef, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(bitmapCxt, CGRectMake(0, 0, width, height), imageRef);
    CGImageRef imageRefWithAlpha = CGBitmapContextCreateImage(bitmapCxt);
    UIImage *imageWithAlpha = [UIImage imageWithCGImage:imageRefWithAlpha];
    
    if (unsupportedColorSpace)
        CGColorSpaceRelease(colorSpaceRef);
    CGImageRelease(imageRefWithAlpha);
    CGContextRelease(bitmapCxt);

    return imageWithAlpha;
}

@end

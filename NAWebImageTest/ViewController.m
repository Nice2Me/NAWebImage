//
//  ViewController.m
//  NYWebImage
//
//  Created by zuopengl on 3/9/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "ViewController.h"
#import "NAWebDataDownloadOperation.h"
#import "NAWebImageManager.h"
#import "NAWebDataOperation.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //
}

- (IBAction)testNSConnection:(id)sender {
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://s3.amazonaws.com/fast-image-cache/demo-images/FICDDemoImage003.jpg"]];

     NAWebDataDownloadOperation *downloaderOp = [[NAWebDataDownloadOperation alloc] initWithRequest:urlRequest progressBlock:^(NSData *data, NSInteger receivedSize, NSInteger expectedSize) {
         NSLog(@"progress");
     } completedBlock:^(NSData *data, NSError *error, BOOL finished) {
         NSLog(@"competion");
     } canceledBlock:^{
         
     }];
    [downloaderOp start];
}


- (IBAction)testNSSession:(id)sender {
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://img2.imgtn.bdimg.com/it/u=771107899,1703862157&fm=21&gp=0.jpg"]];
    NAWebDataDownloadOperation *downloaderOp = [[NAWebDataDownloadOperation alloc] initWithRequest:urlRequest progressBlock:^(NSData *data, NSInteger receivedSize, NSInteger expectedSize) {
        
    } completedBlock:^(NSData *data, NSError *error, BOOL finished) {
        
    } canceledBlock:^{
        
    }];
    
    downloaderOp.sessionTask = YES;
    [downloaderOp start];
}

- (IBAction)testImageDownloader:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://s3.amazonaws.com/fast-image-cache/demo-images/FICDDemoImage003.jpg"];
//    [[NAWebDataDownloader sharedDownloader] downloadImageWithURL:url options:0 progressBlock:^(NSInteger receivedSize, NSInteger expectedSize) {
//        NSLog(@"progress");
//    } completedBlock:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
//        NSLog(@"completed");
//    }];
    [[NAWebImageManager sharedManager] na_downloadImageForURL:url options:0 progress:^(NSInteger receivedSize, NSInteger expectedSize) {
        
    } completion:^(UIImage *image, NSURL *imageUrl, NAImageCacheType cacheType, NSError *error, BOOL finished) {
        
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

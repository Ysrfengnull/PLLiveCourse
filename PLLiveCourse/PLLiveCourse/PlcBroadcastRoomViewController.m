//
//  PlcBroadcastRoomViewController.m
//  PLLiveCourse
//
//  Created by TaoZeyu on 16/8/2.
//  Copyright © 2016年 com.pili-engineering. All rights reserved.
//

#import "PlcBroadcastRoomViewController.h"
#import "AppDelegate.h"

#import <PLCameraStreamingKit/PLCameraStreamingKit.h>

@interface PlcBroadcastRoomViewController ()
@property (nonatomic, strong) PLCameraStreamingSession *cameraStreamingSession;
@property (nonatomic, strong) NSString *roomID;
@end

@implementation PlcBroadcastRoomViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.titleView = ({
        UILabel *label = [[UILabel alloc] init];
        label.text = @"直播房间";
        [label sizeToFit];
        label;
    });
    
    self.cameraStreamingSession = [self _generateCameraStreamingSession];
    
    [self.cameraStreamingSession setBeautify:1.0];
    [self.cameraStreamingSession setWaterMarkWithImage:[UIImage imageNamed:@"qiniu.png"]
                                              position:CGPointMake(100, 100)];
    
    [self requireDevicePermissionWithComplete:^(BOOL granted) {
        
        if (granted) {
            // 获取了设备权限，此时显示出 preview。
            [self.view addSubview:({
                UIView *preview = self.cameraStreamingSession.previewView;
                preview.frame = self.view.bounds;
                preview.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                UIViewAutoresizingFlexibleHeight;
                preview;
            })];
        } else {
            // 没有获取设备权限（或用户拒绝给权限）此时不可能进行推流了，直接退出房间。
            UIAlertController *av = [UIAlertController alertControllerWithTitle:@"却少摄像头或麦克风权限"
                                                                        message:@"即将退出房间"
                                                                 preferredStyle:UIAlertControllerStyleAlert];
            [av addAction:[UIAlertAction actionWithTitle:@"关闭直播"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction * _Nonnull action) {
                                                     [self.navigationController popViewControllerAnimated:YES];
                                                 }]];
            [self presentViewController:av animated:true completion:nil];
        }
    }];
    
    __weak typeof(self) weakSelf = self;
    [self _generatePushURLWithComplete:^(PLStream *stream) {
        
        __strong typeof(self) strongSelf = weakSelf;
        // 当收到 pushURL 时，view controoler 可能已经提前关闭和销毁，此时不可进行推流
        if (strongSelf) {
            strongSelf.cameraStreamingSession.stream = stream;
            [strongSelf.cameraStreamingSession startWithCompleted:^(BOOL success) {
                if (!success) {
                    NSLog(@"推流失败!!");
                }
            }];
        }
    }];
}

- (void)viewDidDisappear:(BOOL)animated
{
    if (self.cameraStreamingSession.isRunning) {
        [self.cameraStreamingSession destroy];
    }
    [self _notifyServerExitRoom];
}

- (void)requireDevicePermissionWithComplete:(void (^)(BOOL granted))complete
{
    switch ([PLCameraStreamingSession cameraAuthorizationStatus]) {
        case PLAuthorizationStatusAuthorized:
            complete(YES);
            break;
        case PLAuthorizationStatusNotDetermined: {
            [PLCameraStreamingSession requestCameraAccessWithCompletionHandler:^(BOOL granted) {
                complete(granted);
            }];
        }
            break;
        default:
            complete(NO);
            break;
    }
}

- (PLCameraStreamingSession *)_generateCameraStreamingSession
{
    // 视频采集配置，对应的是摄像头。
    PLVideoCaptureConfiguration *videoCaptureConfiguration;
    // 视频推流配置，对应的是推流出去的画面。
    PLVideoStreamingConfiguration *videoStreamingConfiguration;
    // 音频采集配置，对应的是麦克风。
    PLAudioCaptureConfiguration *audioCaptureConfiguration;
    // 音频推流配置，对应的是推流出去的声音。
    PLAudioStreamingConfiguration *audioSreamingConfiguration;
    
    videoCaptureConfiguration = [PLVideoCaptureConfiguration defaultConfiguration];
    videoStreamingConfiguration = [PLVideoStreamingConfiguration defaultConfiguration];
    audioCaptureConfiguration = [PLAudioCaptureConfiguration defaultConfiguration];
    audioSreamingConfiguration = [PLAudioStreamingConfiguration defaultConfiguration];
    
    AVCaptureVideoOrientation captureOrientation = AVCaptureVideoOrientationPortrait;

    PLStream *stream = nil;
    return [[PLCameraStreamingSession alloc] initWithVideoCaptureConfiguration:videoCaptureConfiguration
                                                     audioCaptureConfiguration:audioCaptureConfiguration
                                                   videoStreamingConfiguration:videoStreamingConfiguration
                                                   audioStreamingConfiguration:audioSreamingConfiguration
                                                                        stream:stream
                                                              videoOrientation:captureOrientation];
}

- (void)_generatePushURLWithComplete:(void (^)(PLStream *stream))complete
{
    NSString *url = [NSString stringWithFormat:@"%@%@", kHost, @"/api/pilipili"];
    NSLog(@"connect to %@", url);
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 10;
    [request setHTTPBody:[@"title=room" dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable responseError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = responseError;
            if (error != nil || response == nil || data == nil) {
                NSLog(@"获取推流 URL 失败 %@", error);
                return;
            }
            NSDictionary *streamJSON = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:&error];
            NSLog(@"streamJSON : %@", streamJSON);
            self.roomID = streamJSON[@"id"];
            PLStream *stream = [PLStream streamWithJSON:streamJSON];
            if (complete) {
                complete(stream);
            }
        });
    }];
    [task resume];
}

- (void)_notifyServerExitRoom
{
    if (self.roomID) {
        NSString *url = [NSString stringWithFormat:@"%@%@%@", kHost, @"/api/pilipili/", self.roomID];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
        request.HTTPMethod = @"DELETE";
        request.timeoutInterval = 10;
        
        [[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
    }
}

@end

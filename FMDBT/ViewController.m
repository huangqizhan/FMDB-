//
//  ViewController.m
//  FMDBT
//
//  Created by hqz on 2019/5/28.
//  Copyright © 2019 8km. All rights reserved.
//

#import "ViewController.h"
#import "DBCore.h"
#import <objc/runtime.h>


static void runloopCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info){
    if (activity == kCFRunLoopEntry) {
        NSLog(@"kCFRunLoopEntry");
    }else if (activity == kCFRunLoopBeforeTimers){
        NSLog(@"kCFRunLoopBeforeTimers");
    }else if (activity == kCFRunLoopBeforeSources){
        NSLog(@"kCFRunLoopBeforeSources");
    }else if (activity == kCFRunLoopBeforeWaiting){
        NSLog(@"kCFRunLoopBeforeWaiting");
    }else if (activity == kCFRunLoopAfterWaiting){
        NSLog(@"kCFRunLoopAfterWaiting");
    }else if (activity == kCFRunLoopExit){
        NSLog(@"kCFRunLoopExit");
    }else if (activity == kCFRunLoopAllActivities){
        NSLog(@"kCFRunLoopAllActivities");
    }
}

@interface ViewController (){
    DataBaseQueue *_queue;
}

@property (nonatomic,strong) NSString *strongName;
@property (nonatomic,copy) NSString *cName;

@property (nonatomic,retain) NSMutableString *muname;

@end




@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self registerIdHandler];
    [self pointerAction];
}
- (void)pointerAction{
    DataModel *model = [DataModel new];
    for (int i = 0; i < 9999; i++) {
        NSLog(@"i = %d",i);
    }
    NSLog(@"func end");
}
- (void)registerIdHandler{
    
    CFRunLoopRef runloop = CFRunLoopGetMain();
    
    CFRunLoopObserverRef observe = CFRunLoopObserverCreate(CFAllocatorGetDefault(), kCFRunLoopBeforeWaiting | kCFRunLoopExit, true, 0xFFFFFF, runloopCallBack, NULL);
    
    CFRunLoopAddObserver(runloop, observe, kCFRunLoopCommonModes);
    CFRelease(observe);
}

@end


@implementation MMM
+ (void)testClassAction{
    NSLog(@"testClassAction");
}
@end



@implementation DataModel

- (NSString *)dataAction{
    return @"123";
}
+ (void)classAction{
    
}
- (void)dealloc{
    NSLog(@"dealloc");
}
@end



@implementation DataModel (Add)
//- (void)dataAction{
//    NSLog(@"dataAction Add");
//}


@end


@implementation NSObject (MM)


- (void)action1{
    NSLog(@"action2");
}
+ (void)classAction{
    NSLog(@"classAction");
}


@end

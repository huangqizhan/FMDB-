//
//  ViewController.h
//  FMDBT
//
//  Created by hqz on 2019/5/28.
//  Copyright © 2019 8km. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController

@property (nonatomic,readonly,assign) BOOL isRead;
@end



@interface MMM : NSObject

+ (void)testClassAction;

@end

@interface DataModel : NSObject

@property (nonatomic,assign) NSUInteger Id;
@property (nonatomic,copy) NSString *name;
@property (nonatomic,copy) NSString *age;

- (NSString *)dataAction;


+ (void)classAction;

@end


@interface DataModel (Add)

//- (void)dataAction;

@end


@interface NSObject (MM)

- (void)action1;


+ (void)classAction;

@end

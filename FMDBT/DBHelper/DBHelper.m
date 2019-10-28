//
//  DBHelper.m
//  FMDBT
//
//  Created by hqz on 2019/6/26.
//  Copyright © 2019 8km. All rights reserved.
//

#import "DBHelper.h"
#import "DBCore.h"

@interface DBHelper ()
///DB执行队列
@property (nonatomic,strong) DataBaseQueue *dbQueue;
///正执行的DB
@property (nonatomic,weak) DataBase *usingDB;
///正在使用的表名
@property (nonatomic,strong) NSMutableArray *usingTableNames;

@end

@implementation DBHelper

+ (instancetype)shareInstance{
    static DBHelper *helper = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        helper = [[DBHelper alloc] init];
    });
    return helper;
}





@end

//
//  DataBaseQueue.h
//  FMDBT
//
//  Created by hqz on 2019/6/24.
//  Copyright © 2019 8km. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class DataBase;

@interface DataBaseQueue : NSObject

/// database path
@property (atomic, retain, nullable) NSString *path;
/// open flags
@property (atomic, readonly) int openFlags;
/// virtual file name 虚拟文件系统
@property (atomic, copy, nullable) NSString *vfsName;

+ (instancetype)dataBaseQueueWithPath:(NSString * _Nullable)path;
+ (instancetype)dataBaseQueueWithUrl:(NSURL * _Nullable)url;
+ (instancetype)dataBaseQueueWithPath:(NSString * _Nullable)aPath flag:(int)openFlags;
+ (instancetype)dataBaseQueueWithUrl:(NSURL * _Nullable)url flag:(int)openFlags;


- (instancetype)initWithPath:(NSString * _Nullable)aPath;
- (instancetype)initWithUrl:(NSURL *_Nullable)url;
- (instancetype)initWithPath:(NSString *)aPath flag:(int)openFlags;
- (instancetype)initWithUrl:(NSURL *)url flag:(int)openFlags;
- (instancetype)initWithPath:(NSString *)aPath flag:(int)openFlags vfsName:(NSString * _Nullable)vfsName;
- (instancetype)initWithUrl:(NSURL *)url flag:(int)openFlags vfsName:(NSString * _Nullable)vfsName;


+ (Class)dataBaseClass;

- (void)close;

- (void)interruput;


/**
 串行队列同步执行

 @param block 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (void)syncInDataBase:(__attribute__((noescape)) void (^)(DataBase *db))block;

/**
 同步事务执行

 @param block 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (void)syncInTransaction:(__attribute__((noescape)) void (^) (DataBase *db , BOOL *rollback))block;


/**
 同步延迟执行事务

 @param block 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (void)syncInDefferedTransaction:(__attribute__((noescape)) void (^)(DataBase *db,BOOL *rollback))block;

/**
 同步保存事务点

 @param blcok 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (NSError *)syncInSavePoint:(__attribute__((noescape)) void (^)(DataBase *db,BOOL *rollback))blcok;


/**
 串行队列异步执行
 
 @param block 异步回调 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (void)asyncInDataBase:(__attribute__((noescape)) void (^)(DataBase *db))block;

/**
 异步事务执行
 
 @param block 异步回调 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (void)asyncInTransaction:(__attribute__((noescape)) void (^) (DataBase *db , BOOL *rollback))block;


/**
 异步延迟执行事务
 
 @param block 异步回调 非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (void)asyncInDefferedTransaction:(__attribute__((noescape)) void (^)(DataBase *db,BOOL *rollback))block;

/**
 异步保存事务点
 
 @param blcok 异步回调  非逃逸闭包  会随着函数作用域销毁而销毁
 */
- (NSError *)asyncInSavePoint:(__attribute__((noescape)) void (^)(DataBase *db,BOOL *rollback))blcok;

@end

NS_ASSUME_NONNULL_END

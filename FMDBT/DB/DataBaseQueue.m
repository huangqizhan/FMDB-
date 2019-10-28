//
//  DataBaseQueue.m
//  FMDBT
//
//  Created by hqz on 2019/6/24.
//  Copyright © 2019 8km. All rights reserved.
//

#import "DataBaseQueue.h"
#import <sqlite3.h>
#import "DataBase.h"

static const void * const kDispatchQueueSpecificKey = &kDispatchQueueSpecificKey;

@interface DataBaseQueue (){
    dispatch_queue_t _queue;
    DataBase    *_db;
}
@end

@implementation DataBaseQueue

+ (instancetype)dataBaseQueueWithPath:(NSString *)path{
    DataBaseQueue *queue = [[self alloc] initWithPath:path];
    DBAutoRelease(queue);
    return queue;
}
+ (instancetype)dataBaseQueueWithUrl:(NSURL *)url{
    DataBaseQueue *queue = [[self alloc] initWithUrl:url];
    DBAutoRelease(queue);
    return queue;
}
+ (instancetype)dataBaseQueueWithPath:(NSString *)aPath flag:(int)openFlags{
    DataBaseQueue *queue = [[self alloc] initWithPath:aPath flag:openFlags];
    DBAutoRelease(queue);
    return queue;
}
+ (instancetype)dataBaseQueueWithUrl:(NSURL *)url flag:(int)openFlags{
    DataBaseQueue *queue = [[self alloc] initWithUrl:url flag:openFlags];
    DBAutoRelease(queue);
    return queue;
}
- (instancetype)init{
    return [self initWithPath:nil];
}
- (instancetype)initWithPath:(NSString *)aPath{
    return [self initWithPath:aPath flag:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE vfsName:nil];
}
- (instancetype)initWithUrl:(NSURL *)url{
    return [self initWithPath:url.path];
}
- (instancetype)initWithUrl:(NSURL *)url flag:(int)openFlags{
    return [self initWithPath:url.path flag:openFlags];
}
- (instancetype)initWithPath:(NSString *)aPath flag:(int)openFlags vfsName:(NSString *)vfsName{
    self = [super init];
    if (self) {
        _db = [[[self class] dataBaseClass] dataBaseWithPath:aPath];
        BOOL success = NO;
#if SQLITE_VERSION_NUMBER >= 3005000
        success = [_db openWithFlags:openFlags];
#else
        success = [_db open];
#endif
        if (!success) {
            NSLog(@"Could not create database queue for path %@", aPath);
            DBRelease(self);
            return 0x00;
        }
        _path = DBReturnRetained(aPath);
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"db.%@", self] UTF8String], NULL);
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
        _openFlags = openFlags;
        _vfsName = vfsName;
    }
    return self;
}
+ (Class)dataBaseClass{
    return [DataBase class];
}
- (void)dealloc{
    DBRelease(_path);
    DBRelease(_vfsName);
    DBRelease(_db);
    if (_queue) {
        DBDispatchQueueRelease(_queue);
        _queue = 0x00;
    }
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}
- (void)close{
    DBRetain(self);
    dispatch_sync(_queue, ^{
        [self->_db close];
        DBRelease(_db);
        self->_db = nil;
    });
    DBRelease(self);
}
- (void)interruput{
    [[self dataBase] interrupt];
}
- (DataBase *)dataBase{
    if (!_db) {
        _db = DBReturnRetained([[[[self class] dataBaseClass] dataBaseClass] dataBaseWithPath:_path]);
        BOOL success = NO;
#if SQLITE_VERSION_NUMBER >= 3005000
        success = [_db openWithFlags:_openFlags vfs:_vfsName];
#else
        success = [_db open];
#endif
        if (!success) {
            NSLog(@"FMDatabaseQueue could not reopen database for path %@", _path);
            DBRelease(_db);
            _db  = 0x00;
            return 0x00;
        }
    }
    return _db;
}
#pragma mark --- 同步
- (void)beginTransaction:(BOOL)useDeferred withBlock:(__attribute__((noescape)) void (^)(DataBase * _Nonnull, BOOL * _Nonnull))block{
    DBRetain(self);
    dispatch_sync(_queue, ^{
        BOOL shouldRollback = NO;
        if (useDeferred) {
            [[self dataBase] beginDeferredTransaction];
        }else{
            [[self dataBase] beginTransaction];
        }
        if (block) block([self dataBase],&shouldRollback);
        if (shouldRollback) {
            [[self dataBase] rollback];
        }else{
            [[self dataBase] commit];
        }
    });
    DBRelease(self);
}
- (void)syncInDataBase:(__attribute__((noescape)) void (^)(DataBase * _Nonnull))block{
#ifndef NDEBUG
    DataBaseQueue *currentQueue = (__bridge id)dispatch_get_specific(&kDispatchQueueSpecificKey);
    assert(currentQueue != self && "inDatabase: was called reentrantly on the same queue, which would lead to a deadlock");
#endif
    DBRetain(self);
    dispatch_sync(_queue, ^{
        DataBase *db = [self dataBase];
        if (block) block(db);
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue inDatabase:]");
#if defined(DEBUG) && DEBUG
            NSSet *openSetCopy = DBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                ResultSet *rs = (ResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    });
    DBRelease(self);
}
- (void)syncInTransaction:(__attribute__((noescape)) void (^) (DataBase *db , BOOL *rollback))block{
    [self beginTransaction:NO withBlock:block];
}
- (void)syncInDefferedTransaction:(__attribute__((noescape)) void (^)(DataBase * _Nonnull, BOOL * _Nonnull))block{
    [self beginTransaction:YES withBlock:block];
}
- (NSError *)syncInSavePoint:(__attribute__((noescape)) void (^)(DataBase * _Nonnull, BOOL * _Nonnull))blcok{
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIdx = 0;
    __block NSError *error = 0x00;
    DBRetain(self);
    dispatch_sync(_queue, ^{
        NSString *name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];
        BOOL shouldRollback = NO;
        if ([[self dataBase] startSavePointWithName:name error:&error]) {
            if (blcok) blcok([self dataBase],&shouldRollback);
            if (shouldRollback) {
                [[self dataBase] rollbackToSavePointWithName:name error:&error];
            }
            [[self dataBase] releaseSavePointWithName:name error:&error];
        }
    });
    DBRelease(self);
    return error;
#else
    NSString *errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"FMDatabase" code:0 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
#endif
}
#pragma mark --- 异步
- (void)asyncBeginTransaction:(BOOL)useDeferred withBlock:(__attribute__((noescape)) void (^)(DataBase * _Nonnull, BOOL * _Nonnull))block{
    DBRetain(self);
    dispatch_async(_queue, ^{
        BOOL shouldRollback = NO;
        if (useDeferred) {
            [[self dataBase] beginDeferredTransaction];
        }else{
            [[self dataBase] beginTransaction];
        }
        if (block) block([self dataBase],&shouldRollback);
        if (shouldRollback) {
            [[self dataBase] rollback];
        }else{
            [[self dataBase] commit];
        }
    });
    DBRelease(self);
}
- (void)asyncInDataBase:(__attribute__((noescape)) void (^)(DataBase *db))block{
#ifndef NDEBUG
    DataBaseQueue *currentQueue = (__bridge id)dispatch_get_specific(&kDispatchQueueSpecificKey);
    assert(currentQueue != self && "inDatabase: was called reentrantly on the same queue, which would lead to a deadlock");
#endif
    DBRetain(self);
    dispatch_async(_queue, ^{
        DataBase *db = [self dataBase];
        if (block) block(db);
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue inDatabase:]");
#if defined(DEBUG) && DEBUG
            NSSet *openSetCopy = DBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                ResultSet *rs = (ResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    });
    DBRelease(self);
}

- (void)asyncInTransaction:(__attribute__((noescape)) void (^) (DataBase *db , BOOL *rollback))block{
    [self asyncBeginTransaction:NO withBlock:block];
}

- (void)asyncInDefferedTransaction:(__attribute__((noescape)) void (^)(DataBase *db,BOOL *rollback))block{
    [self asyncBeginTransaction:YES withBlock:block];
}

- (NSError *)asyncInSavePoint:(__attribute__((noescape)) void (^)(DataBase *db,BOOL *rollback))blcok{
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIdx = 0;
    __block NSError *error = 0x00;
    DBRetain(self);
    dispatch_async(_queue, ^{
        NSString *name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];
        BOOL shouldRollback = NO;
        if ([[self dataBase] startSavePointWithName:name error:&error]) {
            if (blcok) blcok([self dataBase],&shouldRollback);
            if (shouldRollback) {
                [[self dataBase] rollbackToSavePointWithName:name error:&error];
            }
            [[self dataBase] releaseSavePointWithName:name error:&error];
        }
    });
    DBRelease(self);
    return error;
#else
    NSString *errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"FMDatabase" code:0 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
#endif
}

@end


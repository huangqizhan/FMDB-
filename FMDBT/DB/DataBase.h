//
//  DataBase.h
//  FMDBT
//
//  Created by hqz on 2019/5/28.
//  Copyright © 2019 8km. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ResultSet.h"

NS_ASSUME_NONNULL_BEGIN
///非ARC
#if !__has_feature(objc_arc)
    #define DBAutoRelease(v) ([v autorelease]);
    #define DBReturnAutoreleased DBAutoRelease
    #define DBRetain(v) ([v retain]);
    #define DBReturnRetained DBRetain
    #define DBRelease(v) ([v release]);
    #define DBDispatchQueueRelease(v) (dispatch_release(v));
#else
    #define DBAutoRelease(v)
    #define DBReturnAutoreleased(v) (v)
    #define DBRetain(v)
    #define DBReturnRetained(v) (v)
    #define DBRelease(v) 

    ///6.0之后GCD支持ARC
    #if OS_OBJECT_USE_OBJC
      #define DBDispatchQueueRelease(v)
    #else
      ///6.0之前GCD不支持ARC
      #define DBDispatchQueueRelease(v) (dispatch_release(v));
    #endif
#endif

///如果系统没有定义 instancetype，则定义使用 id 类型定义一个 instancetype 的宏。id 可以做参数可以做返回值，instancetype 只能做返回值。
#if !__has_feature(objc_instanceType)
    #define instanceType id
#endif


typedef int(^DBEcecuteStatementsCallBackBlock) (NSDictionary *resultDictionary);


/**
 
 ///使用说明
 主要的有三个类
 1: DataBase    一个单一的sqlite 数据库  可以执行sql语句
 2: ResultSet 查询语句执行的结果
 3: DataBaseQueue 同时执行多条sql 可以使用此队列
 
 DataBasePool 用来存放DataBase
 Statement  用来封装sql语句
 
 注意： 不要创建一个DataBase 在多线程使用   如果有多线程请使用DataBaseQueue  要么每个线程都要创建自己的DataBase 
 
 **/

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"

@interface DataBase : NSObject
///是否追踪执行sql 
@property (nonatomic,assign) BOOL traceExection;
///
@property (nonatomic,assign) BOOL checkedOut;
///是否打印日志
@property (nonatomic,assign) BOOL crashOnErrors;
/// 
@property (nonatomic,assign) BOOL logsErrors;
///缓存 sql
@property (nonatomic,strong,nullable) NSMutableDictionary *cachedStatements;

#pragma mark ---- init
+ (instancetype)dataBaseWithPath:(NSString * _Nullable)path;
+ (instancetype)dataBaseWithUrl:(NSURL *_Nullable)url;
- (instancetype)initWithPath:(NSString * _Nullable)path;
- (instancetype)initWithUrl:(NSURL * _Nullable)url;

#pragma mark --- open close
- (BOOL)open;
/*
 SQLITE_OPEN_NOMUTEX: 设置数据库连接运行在多线程模式(没有指定单线程模式的情况下)
 SQLITE_OPEN_FULLMUTEX：设置数据库连接运行在串行模式。
 SQLITE_OPEN_SHAREDCACHE：设置运行在共享缓存模式。
 SQLITE_OPEN_PRIVATECACHE：设置运行在非共享缓存模式。
 SQLITE_OPEN_READWRITE：指定数据库连接可以读写。
 SQLITE_OPEN_CREATE：如果数据库不存在，则创建。
 */
- (BOOL)openWithFlags:(int)openflag;

/**
 打开数据库
 @param flags 线程配置  读写配置
 @param vfsName 系统文件系统名称 windows  unix
 @return bool
 */
- (BOOL)openWithFlags:(int)flags vfs:(NSString * _Nullable)vfsName;
/**
 关闭数据库
 @return bool
 */
- (BOOL)close;
///数据库连接是否良好
@property (nonatomic, readonly) BOOL goodConnection;
#pragma mark ------ 增删改
- (BOOL)executeUpdate:(NSString*)sql withErrorAndBindings:(NSError * _Nullable *)outErr, ...;

/**
 sqlu语句参数拼接

 @param sql @"INSERT INTO person(person_id,person_name,person_age,person_number)VALUES(?,?,?,?)" @(2),@"h",@(2),@(2),nil 参数必须是对象类型
 @return BOOL
 */
- (BOOL)executeUpdate:(NSString*)sql, ...;

/**
 增删改 字符串拼接类型
 NS_FORMAT_FUNCTION(1,2) 第一个参数是拼接类型字符串 其他事任意类型
 @param format 拼接字符串
 @return bool
 */
- (BOOL)executeUpdateWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 sql拼接 sql @"INSERT INTO person(person_id,person_name,person_age,person_number)VALUES(?,?,?,?)"

 @param sql @"INSERT INTO person(person_id,person_name,person_age,person_number)VALUES(?,?,?,?)"
 @param arguments 参数数组
 @return bool
 */
- (BOOL)executeUpdate:(NSString*)sql withArgumentsInArray:(NSArray *)arguments;
- (BOOL)executeUpdate:(NSString*)sql values:(NSArray * _Nullable)values error:(NSError * _Nullable __autoreleasing *)error;


/**
 sql 拼接

 @param sql @"INSERT INTO person(person_id,person_name,person_age,person_number)VALUES(?,?,?,?)"
 @param arguments 参数字典
 @return bool
 */
- (BOOL)executeUpdate:(NSString*)sql withParameterDictionary:(NSDictionary *)arguments;

/**
 sql 拼接
 @param sql @"INSERT INTO person(person_id,person_name,person_age,person_number)VALUES(?,?,?,?)"
 @param args arglist
 @return bool
 */
- (BOOL)executeUpdate:(NSString*)sql withVAList: (va_list)args;




/**
 sqlite3_exec  可执行多条sql
 sqlite3_exec() 就是把你提到的三个函数结合在了一起：sqlite3_step()， sqlite3_perpare()， sqlite3_finalize()。
 然后提供一个回调函数进行结果的处理。
 @param sql sql
 @return bool
 */
- (BOOL)executeStatements:(NSString *)sql;

/**
 sqlite3_exec
 sqlite3_exec() 就是把你提到的三个函数结合在了一起：sqlite3_step()， sqlite3_perpare()， sqlite3_finalize()。
 @param sql sql
 @param block 每条sql的执行回调
 @return bool
 */
- (BOOL)executeStatements:(NSString *)sql withResultBlock:(__attribute__((noescape)) DBEcecuteStatementsCallBackBlock _Nullable)block;
///最后插入行的ID
@property (nonatomic, readonly) int64_t lastInsertRowId;
///修改的行数
@property (nonatomic, readonly) int changes;


#pragma mark --- 查询
///sql : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 
- (ResultSet * _Nullable)executeQuery:(NSString*)sql, ...;
///format : @"select *from tablename where Id = %@ and name = '%@'",@(11),@"hqz"
- (ResultSet * _Nullable)executeQueryWithFormat:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);
- (ResultSet * _Nullable)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arguments;
- (ResultSet * _Nullable)executeQuery:(NSString *)sql values:(NSArray * _Nullable)values error:(NSError * _Nullable __autoreleasing *)error;
- (ResultSet * _Nullable)executeQuery:(NSString *)sql withParameterDictionary:(NSDictionary * _Nullable)arguments;
- (ResultSet * _Nullable)executeQuery:(NSString *)sql withVAList:(va_list)args;


#pragma mark ---  事务
- (BOOL)beginTransaction;
- (BOOL)beginDeferredTransaction;
- (BOOL)commit;
- (BOOL)rollback;
@property (nonatomic, readonly) BOOL isInTransaction;

///清空sqlite3_stmt
- (void)clearCachedStatements;
///清空结果
- (void)closeOpenResultSets;
///是否有缓存的结果
@property (nonatomic, readonly) BOOL hasOpenResultSets;
///是否缓存sql 
@property (nonatomic) BOOL shouldCacheStatements;


- (BOOL)interrupt;

///sqlite 加密
- (BOOL)setKey:(NSString*)key;
- (BOOL)rekey:(NSString*)key;
- (BOOL)setKeyWithData:(NSData *)keyData;
- (BOOL)rekeyWithData:(NSData *)keyData;


@property (nonatomic, readonly, nullable) NSString *databasePath;
@property (nonatomic, readonly, nullable) NSURL *databaseURL;
///sqlite db pointer
@property (nonatomic, readonly) void *sqliteHandle;


- (NSString*)lastErrorMessage;
- (int)lastErrorCode;

- (int)lastExtendedErrorCode;
- (BOOL)hadError;


- (NSError *)lastError;
///当数据库被其他线程持有时 sqlite3 重新连接的时间戳限制 
@property (nonatomic) NSTimeInterval maxBusyRetryTimeInterval;

//// 事务点
- (BOOL)startSavePointWithName:(NSString*)name error:(NSError * _Nullable *)outErr;
- (BOOL)releaseSavePointWithName:(NSString*)name error:(NSError * _Nullable *)outErr;
- (BOOL)rollbackToSavePointWithName:(NSString*)name error:(NSError * _Nullable *)outErr;

/// I do not konw what is the use
- (NSError * _Nullable)inSavePoint:(__attribute__((noescape)) void (^)(BOOL *rollback))block;

+ (BOOL)isSQLiteThreadSafe;
+ (NSString*)sqliteLibVersion;
+ (NSString*)DBUserVersion;
+ (SInt32)DBVersion;


/**
 添加sql 函数
 @param name 函数名
 @param arguments 参数
 @param block 函数回调
 */
- (void)makeFunctionNamed:(NSString *)name arguments:(int)arguments block:(void (^)(void *context, int argc, void * _Nonnull * _Nonnull argv))block;


typedef NS_ENUM(int, SqliteValueType) {
    SqliteValueTypeInteger = 1,
    SqliteValueTypeFloat   = 2,
    SqliteValueTypeText    = 3,
    SqliteValueTypeBlob    = 4,
    SqliteValueTypeNull    = 5
};

#pragma mark 自定义方法参数设置
///自定义方法参数类型获取
- (SqliteValueType)valueType:(void *)argv;
- (int)valueInt:(void *)value;
- (long long)valueLong:(void *)value;
- (double)valueDouble:(void *)value;
- (NSData * _Nullable)valueData:(void *)value;
- (NSString * _Nullable)valueString:(void *)value;
///自定义方法参数设置
- (void)resultNullInContext:(void *)context NS_SWIFT_NAME(resultNull(context:));
- (void)resultInt:(int) value context:(void *)context;
- (void)resultLong:(long long)value context:(void *)context;
- (void)resultDouble:(double)value context:(void *)context;
- (void)resultData:(NSData *)data context:(void *)context;
- (void)resultString:(NSString *)value context:(void *)context;
- (void)resultError:(NSString *)error context:(void *)context;
- (void)resultErrorCode:(int)errorCode context:(void *)context;
- (void)resultErrorNoMemoryInContext:(void *)context NS_SWIFT_NAME(resultErrorNoMemory(context:));
- (void)resultErrorTooBigInContext:(void *)context NS_SWIFT_NAME(resultErrorTooBig(context:));

///时间存储设置
+ (NSDateFormatter *)storeableDateFormat:(NSString *)format;
- (BOOL)hasDateFormatter;
- (void)setDateFormat:(NSDateFormatter *)format;
- (NSDate * _Nullable)dateFromString:(NSString *)s;
- (NSString *)stringFromDate:(NSDate *)date;

@end


/**
  封装  sqlite3_stmt 
 */
@interface Statement : NSObject{
    void *_statement;
    NSString *_query;
    long _useCount;
    BOOL _inUse;
}
@property (atomic, assign) long useCount;
@property (atomic, retain) NSString *query;
@property (atomic, assign) void *statement;
@property (atomic, assign) BOOL inUse;

- (void)close;
- (void)reset;

@end

#pragma clang diagnostic pop

NS_ASSUME_NONNULL_END

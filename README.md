# FMDB- 学习记录 

### DataBse 

>MRC  ARC  内存管理 

```
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
```

> 使用说明
 主要的有三个类
 1: DataBase    一个单一的sqlite 数据库  可以执行sql语句
 2: ResultSet 查询语句执行的结果
 3: DataBaseQueue 同时执行多条sql 可以使用此队列
 
 > DataBasePool 用来存放DataBase
 Statement  用来封装sql语句
 
 > 注意： 不要创建一个DataBase 在多线程使用   如果有多线程请使用DataBaseQueue  要么每个线程都要创建自己的DataBase 

```

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

```

> 封装  sqlite3_stmt 

```
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
```



```

///程序运行过程中，如果有其他进程或者线程在读写数据库，那么sqlite3_busy_handler会不断调用回调函数，直到其他进程或者线程释放锁。获得锁之后，不会再调用回调函数，从而向下执行，进行数据库操作。该函数是在获取不到锁的时候，以执行回调函数的次数来进行延迟，等待其他进程或者线程操作数据库结束，从而获得锁操作数据库。
static int (DBBaseBusyHandler)(void *f , int count){
    DataBase *self = (__bridge DataBase *)f;
    if (count == 0) {
        self->_startBusyRetryTime = [NSDate timeIntervalSinceReferenceDate];
        return 1;
    }
    NSTimeInterval datele = [NSDate timeIntervalSinceReferenceDate] - (self->_startBusyRetryTime);
     // 当挂起的时长大于maxBusyRetryTimeInterval，就返回0，并停止执行该回调函数了
    if (datele < [self maxBusyRetryTimeInterval]) {
        // 使用sqlite3_sleep每次当前线程挂起50~100ms
        int requestedSleepInmillseconds = (int) arc4random_uniform(50) + 50;
        int actualSleepInmillseconds = sqlite3_sleep(requestedSleepInmillseconds);
        if (requestedSleepInmillseconds != actualSleepInmillseconds) {
             // 如果实际挂起的时长与想要挂起的时长不一致，可能是因为构建SQLite时没将HAVE_USLEEP置为1
            NSLog(@"WARNING: Requested sleep of %i milliseconds, but SQLite returned %i. Maybe SQLite wasn't built with HAVE_USLEEP=1?", requestedSleepInmillseconds, actualSleepInmillseconds);
        }
        return 1;
    }
    return 0;
}

```


```
/**
 提取sql
 @param sql @"select *from %@ where userName = '%@' and userId = %ld and age = %ld"
 @param args @"mytable",@"hhh",111,2,nil
 @param cleanedSQL [NSMutableString stringWithCapacity:[sql length]]
 @param arguments 参数数值
 
  eg: sql   [self executeQueryWithFormat:@"select *from %@ where userName = '%@' and userId = %ld and age = %ld",@"mytable",@"hhh",111,2,nil];
 生成的参数数组  ： (
            mytable,
            hhh,
            111,
            2
 )
 替换之后的sql: sql = select *from ? where userName = '?' and userId = ? and age = ?
 */
- (void)extractSQL:(NSString *)sql argumentsList:(va_list)args intoString:(NSMutableString *)cleanedSQL arguments:(NSMutableArray *)arguments {
    
    NSUInteger length = [sql length];
    unichar last = '\0';
    for (NSUInteger i = 0; i < length; ++i) {
        id arg = nil;
        unichar current = [sql characterAtIndex:i];
        unichar add = current;
        if (last == '%') {
            switch (current) {
                case '@':
                    arg = va_arg(args, id);
                    break;
                case 'c':
                    // warning: second argument to 'va_arg' is of promotable type 'char'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                    arg = [NSString stringWithFormat:@"%c", va_arg(args, int)];
                    break;
                case 's':
                    arg = [NSString stringWithUTF8String:va_arg(args, char*)];
                    break;
                case 'd':
                case 'D':
                case 'i':
                    arg = [NSNumber numberWithInt:va_arg(args, int)];
                    break;
                case 'u':
                case 'U':
                    arg = [NSNumber numberWithUnsignedInt:va_arg(args, unsigned int)];
                    break;
                case 'h':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        //  warning: second argument to 'va_arg' is of promotable type 'short'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                        arg = [NSNumber numberWithShort:(short)(va_arg(args, int))];
                    }
                    else if (i < length && [sql characterAtIndex:i] == 'u') {
                        // warning: second argument to 'va_arg' is of promotable type 'unsigned short'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                        arg = [NSNumber numberWithUnsignedShort:(unsigned short)(va_arg(args, uint))];
                    }
                    else {
                        i--;
                    }
                    break;
                case 'q':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        arg = [NSNumber numberWithLongLong:va_arg(args, long long)];
                    }
                    else if (i < length && [sql characterAtIndex:i] == 'u') {
                        arg = [NSNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                    }
                    else {
                        i--;
                    }
                    break;
                case 'f':
                    arg = [NSNumber numberWithDouble:va_arg(args, double)];
                    break;
                case 'g':
                    // warning: second argument to 'va_arg' is of promotable type 'float'; this va_arg has undefined behavior because arguments will be promoted to 'double'
                    arg = [NSNumber numberWithFloat:(float)(va_arg(args, double))];
                    break;
                case 'l':
                    i++;
                    if (i < length) {
                        unichar next = [sql characterAtIndex:i];
                        if (next == 'l') {
                            i++;
                            if (i < length && [sql characterAtIndex:i] == 'd') {
                                //%lld
                                arg = [NSNumber numberWithLongLong:va_arg(args, long long)];
                            }
                            else if (i < length && [sql characterAtIndex:i] == 'u') {
                                //%llu
                                arg = [NSNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                            }
                            else {
                                i--;
                            }
                        }
                        else if (next == 'd') {
                            //%ld
                            arg = [NSNumber numberWithLong:va_arg(args, long)];
                        }
                        else if (next == 'u') {
                            //%lu
                            arg = [NSNumber numberWithUnsignedLong:va_arg(args, unsigned long)];
                        }
                        else {
                            i--;
                        }
                    }
                    else {
                        i--;
                    }
                    break;
                default:
                    // something else that we can't interpret. just pass it on through like normal
                    break;
            }
        }
        else if (current == '%') {
            // percent sign; skip this character
            add = '\0';
        }
        
        if (arg != nil) {
            [cleanedSQL appendString:@"?"];
            [arguments addObject:arg];
        }
        else if (add == (unichar)'@' && last == (unichar) '%') {
            [cleanedSQL appendFormat:@"NULL"];
        }
        else if (add != '\0') {
            [cleanedSQL appendFormat:@"%C", add];
        }
        last = current;
    }
}

```

> DataBase (DataBaseAddtional) 扩展 


```

@interface DataBase (DataBaseAddtional) 

///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz"  第一列string
- (NSString *)stringForQuery:(NSString*)query, ...;
///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 第一列int
- (int)intForQuery:(NSString*)query, ...;
///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 第一列long
- (long)longForQuery:(NSString*)query, ...;
///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 第一列bool
- (BOOL)boolForQuery:(NSString*)query, ...;
///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 第一列double
- (double)doubleForQuery:(NSString*)query, ...;
///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 第一列data
- (NSData * _Nullable)dataForQuery:(NSString*)query, ...;
///query : @"select *from tablename where Id = ? and name = '?'",@(11),@"hqz" 第一列 date
- (NSDate * _Nullable)dateForQuery:(NSString*)query, ...;
///表是否存在
- (BOOL)tableExists:(NSString*)tableName;

///数据库的系统表信息
- (ResultSet *)getSchema;

///某张表的信息
- (ResultSet*)getTableSchema:(NSString*)tableName;

///表是否存在每个字段
- (BOOL)columnExists:(NSString*)columnName inTableWithName:(NSString*)tableName;
///校验sql 不会执行sql 只是sqlite3_prepare_v2 sqlite3_finalize
- (BOOL)validateSQL:(NSString*)sql error:(NSError * _Nullable *)error;

@property (nonatomic) uint32_t applicationID;

@property (nonatomic) uint32_t userVersion;
@end

``` 

> DataBaseQueue  sql 执行队列 

```
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
```



> 执行结果的分装 

```
@interface ResultSet : NSObject

///database
@property (nonatomic, retain, nullable) DataBase *parentDB;
///sql
@property (atomic, retain, nullable) NSString *query;
////columnName dictionary
@property (readonly) NSMutableDictionary *columnNameToIndexMap;
/// sqlite3_stmt
@property (atomic, retain, nullable) Statement *statement;

/**
 一个ResultSet对应一个 sqlite3_stmt 对应一个 DataBase

 @param statement sqlite3_stmt
 @param aDB DataBase
 @return self
 */
+ (instancetype)resultSetWithStatement:(Statement *)statement usingParentDatabase:(DataBase*)aDB;
///关闭 sqlite3_stmt
- (void)close;
///是否有下一行
- (BOOL)next;
- (BOOL)nextWithError:(NSError * _Nullable *)outErr;

- (BOOL)hasAnotherRow;
//列数
@property (nonatomic, readonly) int columnCount;
///列对应的索引
- (int)columnIndexForName:(NSString*)columnName;
///列索引对应的列名
- (NSString * _Nullable)columnNameForIndex:(int)columnIdx;
///colmun -> int
- (int)intForColumn:(NSString*)columnName;
- (int)intForColumnIndex:(int)columnIdx;

///column ->long
- (long)longForColumn:(NSString*)columnName;
- (long)longForColumnIndex:(int)columnIdx;
///column -> long long
- (long long int)longLongIntForColumn:(NSString*)columnName;
- (long long int)longLongIntForColumnIndex:(int)columnIdx;
///column -> unsigned long long
- (unsigned long long int)unsignedLongLongIntForColumn:(NSString*)columnName;
- (unsigned long long int)unsignedLongLongIntForColumnIndex:(int)columnIdx;
///column -> bool
- (BOOL)boolForColumn:(NSString*)columnName;
- (BOOL)boolForColumnIndex:(int)columnIdx;

///column -> double
- (double)doubleForColumn:(NSString*)columnName;
- (double)doubleForColumnIndex:(int)columnIdx;

///column -> string
- (NSString * _Nullable)stringForColumn:(NSString*)columnName;
- (NSString * _Nullable)stringForColumnIndex:(int)columnIdx;

/// column -> date
- (NSDate * _Nullable)dateForColumn:(NSString*)columnName;
- (NSDate * _Nullable)dateForColumnIndex:(int)columnIdx;
///column -> data
- (NSData * _Nullable)dataForColumn:(NSString*)columnName;
- (NSData * _Nullable)dataForColumnIndex:(int)columnIdx;

///column -> utf8 sting
- (const unsigned char * _Nullable)UTF8StringForColumn:(NSString*)columnName;
- (const unsigned char * _Nullable)UTF8StringForColumnIndex:(int)columnIdx;
///column -> objc
- (id _Nullable)objectForColumn:(NSString*)columnName;
- (id _Nullable)objectAtIndexedSubscript:(int)columnIdx;
- (id _Nullable)objectForKeyedSubscript:(NSString *)columnName;

/// NS_RETURNS_NOT_RETAINED表示这个方法返回的对象，不需要被release，而NS_RETURNS_RETAINED则表示方法所返回的对象需要被release
- (NSData * _Nullable)dataNoCopyForColumn:(NSString *)columnName NS_RETURNS_NOT_RETAINED;
- (NSData * _Nullable)dataNoCopyForColumnIndex:(int)columnIdx NS_RETURNS_NOT_RETAINED;

///column is null
- (BOOL)columnIndexIsNull:(int)columnIdx;
- (BOOL)columnIsNull:(NSString*)columnName;
///一行数据列名对应的value
@property (nonatomic, readonly, nullable) NSDictionary *resultDictionary;
///一行对应一 object
- (void)kvcMagic:(id)object;

@end


```



> 其他记录 


```

   在执行任何SQL语句之前，必须首先连接到一个数据库，也就是打开或者新建一个SQlite3数据库文件。连接数据库由sqlite3_open函数完成，它一共有上面3个版本。其中 sqlite3_open函数假定SQlite3数据库文件名为UTF-8编码，sqlite3_open_v2是它的加强版。sqlite3_open16函数假定SQlite3数据库文件名为UTF-16（Unicode宽字符）编码。
 
 
   所有这三个函数，参数filename是要连接的SQlite3数据库文件名字符串。参数ppDb看起来有点复杂，它是一个指向指针的指针。当调用sqlite3_open_xxx函数时，该函数将分配一个新的SQlite3数据结构，然后初始化，然后将指针ppDb指向它。所以客户应用程序可以通过sqlite3_open_xxx函数连接到名为filename的数据库，并通过参数ppDb返回指向该数据库数据结构的指针。
 
   对于sqlite3_open和sqlite3_open16函数，如果可能将以可读可写的方式打开数据库，否则以只读的方式打开数据库。如果要打开的数据库文件不存在，就新建一个。对于 函数，情况就要复杂一些了，因为这个v2版本的函数强大就强大在它可以对打开（连接）数据库的方式进行控制，具体是通过它的参数flags来完成。sqlite3_open_v2函数只支持UTF-8编码的SQlite3数据库文件。
 
   如flags设置为SQLITE_OPEN_READONLY，则SQlite3数据库文件以只读的方式打开，如果该数据库文件不存在，则sqlite3_open_v2函数执行失败，返回一个error。如果flags设置为SQLITE_OPEN_READWRITE，则SQlite3数据库文件以可读可写的方式打开，如果该数据库文件本身被操作系统设置为写保护状态，则以只读的方式打开。如果该数据库文件不存在，则sqlite3_open_v2函数执行失败，返回一个error。如果flags设置为SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE，则SQlite3数据库文件以可读可写的方式打开，如果该数据库文件不存在则新建一个。这也是sqlite3_open和sqlite3_open16函数的默认行为。除此之外，flags还可以设置为其他标志，具体可以查看SQlite官方文档。
 
   参数zVfs允许客户应用程序命名一个虚拟文件系统（Virtual File System）模块，用来与数据库连接。VFS作为SQlite library和底层存储系统（如某个文件系统）之间的一个抽象层，通常客户应用程序可以简单的给该参数传递一个NULL指针，以使用默认的VFS模块。 有unix  windows
 
   unix :
  unix-dotfile - uses dot-file locking rather than POSIX advisory locks.
   unix-excl - obtains and holds an exclusive lock on database files, preventing other processes from accessing the database. Also keeps the wal-index in heap rather than in shared memory.
   unix-none - all file locking operations are no-ops.
   unix-namedsem - uses named semaphores for file locking. VXWorks only.
 
  windows:
 win32-longpath - like "win32" except that pathnames can be up to 65534 bytes in length, whereas pathnames max out at 1040 bytes in "win32".
 
win32-none - all file locking operations are no-ops.
 
 win32-longpath-none - combination of "win32-longpath" and "win32-none" - long pathnames are supported and all lock operations are no-ops.

 
   对于UTF-8编码的SQlite3数据库文件，推荐使用sqlite3_open_v2函数进行连接，它可以对数据库文件的打开和处理操作进行更多的控制。
 
   SQlite3数据库文件的扩展名没有一个标准定义，比较流行的选择是.sqlite3、.db、.db3。不过在Windows系统平台上，不推荐使用.sdb作为 SQlite3数据库文件的扩展名，据说这会导致IO速度显著减慢，因为.sdb扩展名有其特殊用义。

```


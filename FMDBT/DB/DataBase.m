//
//  DataBase.m
//  FMDBT
//
//  Created by hqz on 2019/5/28.
//  Copyright © 2019 8km. All rights reserved.
//

#import "DataBase.h"
#import "unistd.h"
#import <objc/runtime.h>
#import <sqlite3.h>



@interface DataBase (){
    void *_db;
    BOOL _isExecutingStatement;
    NSTimeInterval _startBusyRetryTime;
    NSMutableSet *_openResultSets;
    NSMutableSet *_openResultFunctions;
    NSDateFormatter *_dateFormat;
}
NS_ASSUME_NONNULL_BEGIN

- (ResultSet * _Nullable)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray* _Nullable)arrayArgs orDictionary:(NSDictionary *_Nullable)dictionaryArgs orVAList:(va_list)args;

- (BOOL)executeUpdate:(NSString*)sql error:(NSError*_Nullable *)outErr withArgumentsInArray:(NSArray* _Nullable)arrayArgs orDictionary:(NSDictionary * _Nullable)dictionaryArgs orVAList:(va_list)args;

NS_ASSUME_NONNULL_END
@end

@implementation DataBase

///需要实现 set get
@synthesize shouldCacheStatements = _shouldCacheStatements;
@synthesize maxBusyRetryTimeInterval = _maxBusyRetryTimeInterval;

#pragma mark --- instancetion dealloction
+ (instancetype)dataBaseWithPath:(NSString * _Nullable)apath{
    return DBReturnAutoreleased([[self alloc] initWithPath:apath]);
}
+ (instancetype)dataBaseWithUrl:(NSURL *)url{
    return DBReturnAutoreleased([[self alloc] initWithUrl:url]);
}
- (instancetype)init {
    return [self initWithPath:nil];
}
- (instancetype)initWithUrl:(NSURL *)url{
    return [self initWithPath:url.path];
}
- (instancetype)initWithPath:(NSString *)path{
    ///1,2 是线程安全的
    assert(sqlite3_threadsafe());
    self = [super init];
    if (self) {
        _databasePath = [path copy];
        _openResultSets = [[NSMutableSet alloc] init];
        _db = nil;
        _logsErrors = YES;
        _crashOnErrors = NO;
        _maxBusyRetryTimeInterval = 2;
    }
    return self;
}

#if !__has_feature(objc_arc)
- (void)finalize{
    [self close];
    [super finalize];
}
#endif
- (void)dealloc{
    [self close];
    DBRelease(_openResultSets);
    DBRelease(_cachedStatements);
    DBRelease(_dateFormat);
    DBRelease(_databasePath);
    DBRelease(_openFunctions);
    
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}
- (NSURL *)databaseURL{
    return _databasePath ? [NSURL URLWithString:_databasePath] : nil;
}
+ (NSString*)DBUserVersion {
    return @"2.7.2";
}
+ (SInt32)DBVersion {
    // we go through these hoops so that we only have to change the version number in a single spot.
    static dispatch_once_t once;
    static SInt32 FMDBVersionVal = 0;
    dispatch_once(&once, ^{
        NSString *prodVersion = [self DBUserVersion];
        if ([[prodVersion componentsSeparatedByString:@"."] count] < 3) {
            prodVersion = [prodVersion stringByAppendingString:@".0"];
        }
        NSString *junk = [prodVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
        char *e = nil;
        FMDBVersionVal = (int) strtoul([junk UTF8String], &e, 16);
    });
    return FMDBVersionVal;
}
#pragma mark SQLite information
+ (NSString*)sqliteLibVersion {
    return [NSString stringWithFormat:@"%s", sqlite3_libversion()];
}
+ (BOOL)isSQLiteThreadSafe {
    // make sure to read the sqlite headers on this guy!
    return sqlite3_threadsafe() != 0;
}
- (void*)sqliteHandle {
    return _db;
}
- (const char*)sqlitePath {
    if (!_databasePath) {
        return ":memory:";
    }
    if ([_databasePath length] == 0) {
        return ""; // this creates a temporary database (it's an sqlite thing).
    }
    return [_databasePath fileSystemRepresentation];
}

#pragma mark --- dataBase open  close
- (BOOL)open{
    if (_db) {
        return YES;
    }
    int error = sqlite3_open([self sqlitePath], (sqlite3 **)&_db);
    if (error != SQLITE_OK) {
        NSLog(@"opening error %d",error);
        return NO;
    }
    if (_maxBusyRetryTimeInterval > 0) {
        [self setMaxBusyRetryTimeInterval:_maxBusyRetryTimeInterval];
    }
    return YES;
}
/*
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
 */

- (BOOL)openWithFlags:(int)openflag{
    return [self openWithFlags:openflag vfs:nil];
}
- (BOOL)openWithFlags:(int)flags vfs:(NSString *)vfsName{
#if SQLITE_VERSION_NUMBER >= 3005000
    if (_db) {
        return YES;
    }
    int err = sqlite3_open_v2([self sqlitePath], (sqlite3**)&_db, flags, vfsName.UTF8String);
    if (err != SQLITE_OK) {
        NSLog(@"error open %d",err);
        return NO;
    }
    if (_maxBusyRetryTimeInterval > 0.0) {
        [self setMaxBusyRetryTimeInterval:_maxBusyRetryTimeInterval];
    }
    return YES;
#else
    NSLog(@"opensqliteFlag require 3.5");
    return NO;
#endif
}
- (BOOL)close{
    [self clearCachedStatements];
    [self closeOpenResultSets];
    if (!_db) {
        return NO;
    }
    int rc;
    BOOL retry;
    BOOL triedFinalzingOpenStatement = NO;
    do {
        retry = NO;
        rc = sqlite3_close(_db);
        if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) {
            if (!triedFinalzingOpenStatement) {
                triedFinalzingOpenStatement = YES;
                ///结束所有的sql
                sqlite3_stmt *Pstmt;
                while ((Pstmt = sqlite3_next_stmt(_db, nil)) != 0 ) {
                    NSLog(@"closing leaked statement");
                    ///The sqlite3_finalize() function is called to delete a prepared statement.
                    sqlite3_finalize(Pstmt);
                    retry = YES;
                }
            }
        }else if (rc != SQLITE_OK){
            NSLog(@"error close");
        }
    } while (retry);
    _db = nil;
    return YES;
}

#pragma mark ---- normal action
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
- (void)setMaxBusyRetryTimeInterval:(NSTimeInterval)maxBusyRetryTimeInterval{
    _maxBusyRetryTimeInterval = maxBusyRetryTimeInterval;
    if (!_db) {
        return;
    }
    if (maxBusyRetryTimeInterval > 0) {
        sqlite3_busy_handler(_db, &DBBaseBusyHandler, (__bridge void *)(self));
    }else{
        sqlite3_busy_handler(_db, nil, nil);
    }
}
- (NSTimeInterval)maxBusyRetryTimeInterval{
    return _maxBusyRetryTimeInterval;
}
#pragma mark --- result sets actions
- (BOOL)hasOpenResultSets{
    return [_openResultSets count] > 0;
}
- (void)closeOpenResultSets{
    NSSet *openResultCopy = DBReturnAutoreleased([_openResultSets copy]);
    for (NSValue *rsInWapperInTastValueMeal in openResultCopy) {
        ResultSet *rs = (ResultSet *)[rsInWapperInTastValueMeal pointerValue];
        [rs setParentDB:nil];
        [rs close];
        [_openResultSets removeObject:rsInWapperInTastValueMeal];
    }
}
- (void)resultSetDidClose:(ResultSet *)result{
    NSValue *setValue = [NSValue valueWithNonretainedObject:result];
    [_openResultSets removeObject:setValue];
}

#pragma mark ---- cached statements
- (void)clearCachedStatements{
    for (NSMutableSet *set in _cachedStatements) {
        for (Statement *state in [set allObjects]) {
            [state close];
        }
    }
    [_cachedStatements removeAllObjects];
}
- (Statement *)cacheStatementForQuery:(NSString *)query{
    NSMutableSet *set = [_cachedStatements objectForKey:query];
    return [[set objectsPassingTest:^BOOL( Statement * _Nonnull obj, BOOL * _Nonnull stop) {
        *stop = ![obj inUse];
        return *stop;
    }] anyObject];
}
- (void)setCachedStatement:(Statement *)statement forQuery:(NSString *)query{
    query = [query copy];
    [statement setQuery:query];
    NSMutableSet *statements = [_cachedStatements objectForKey:query];
    if (!statements) {
        statements = [NSMutableSet new];
    }
    [statements addObject:statement];
    [_cachedStatements setObject:statements forKey:query];
    DBRelease(query);
}

#pragma mark --- key routines
- (BOOL)rekey:(NSString *)key{
    NSData *data = [NSData dataWithBytes:(void *)[key UTF8String] length:(NSInteger)strlen([key UTF8String])];
    return [self rekeyWithData:data];
}
- (BOOL)rekeyWithData:(NSData *)keyData{
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }
    int rc = sqlite3_rekey(_db, [keyData bytes], (int)[keyData length]);
    if (rc != SQLITE_OK) {
        NSLog(@"error on rekey: %d", rc);
        NSLog(@"%@", [self lastErrorMessage]);
    }
    return (rc == SQLITE_OK);
#else
#pragma unused(keyData)
    return NO;
#endif
}
- (BOOL)setKey:(NSString *)key{
    NSData *data = [NSData dataWithBytes:(void *)[key UTF8String] length:(NSInteger)strlen([key UTF8String])];
    return [self setKeyWithData:data];
}
- (BOOL)setKeyWithData:(NSData *)keyData{
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }
    
    int rc = sqlite3_key(_db, [keyData bytes], (int)[keyData length]);
    return (rc == SQLITE_OK);
#else
#pragma unused(keyData)
    return NO;
#endif
}
#pragma mark --- date routines

+ (NSDateFormatter *)storeableDateFormat:(NSString *)format{
    NSDateFormatter *formater = DBReturnAutoreleased([[NSDateFormatter alloc] init]);
    formater.dateFormat = format;
    formater.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formater.locale = DBReturnAutoreleased([[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]);
    return formater;
}
- (BOOL)hasDateFormatter{
    return _dateFormat != nil;
}
- (void)setDateFormat:(NSDateFormatter *)format{
    DBAutoRelease(_dateFormat);
    _dateFormat = DBReturnAutoreleased(format);
}
- (NSDate *)dateFromString:(NSString *)s{
    return [_dateFormat dateFromString:s];
}
- (NSString *)stringFromDate:(NSDate *)date{
    return [_dateFormat stringFromDate:date];
}
#pragma mark --- state DataBase
- (BOOL)goodConnection{
    if (!_db) {
        return NO;
    }
    ResultSet *result = [self executeQuery:@"select name from sqlite_master where type='table'"];
    if (result) {
        [result close];
        return YES;
    }
    return NO;
}
- (void)warnInUse{
    NSLog(@"The Database %@ is currently in use.", self);
///DEBUG下的代码
#if NS_BLOCK_ASSERTIONS
    NSAssert(false, @"The Database %@ is currently in use.", self);
    abort();
#endif
}
- (BOOL)databaseExists{
    if (!_db) {
        NSLog(@"The Database %@ is not open.", self);
        
#ifndef NS_BLOCK_ASSERTIONS
        if (_crashOnErrors) {
            NSAssert(false, @"The Database %@ is not open.", self);
            abort();
        }
#endif
        return NO;
    }
    return YES;
}
#pragma mark  error rountines
- (NSString *)lastErrorMessage{
    return [NSString stringWithUTF8String:sqlite3_errmsg(_db)];
}
- (BOOL)hadError{
    int lastErrCode = [self lastErrorCode];
    return (lastErrCode > SQLITE_OK && lastErrCode < SQLITE_ROW);
}
- (int)lastErrorCode{
    return sqlite3_errcode(_db);
}
- (int)lastExtendedErrorCode{
    return sqlite3_extended_errcode(_db);
}
- (NSError*)errorWithMessage:(NSString *)message{
    NSDictionary *info = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:@"database" code:sqlite3_errcode(_db) userInfo:info];
}
- (NSError *)lastError{
    return [self errorWithMessage:[self lastErrorMessage]];
}
- (sqlite_int64)lastInsertRowId{
    if (_isExecutingStatement) {
        [self warnInUse];
        return 0;
    }
    _isExecutingStatement = YES;
    sqlite_int64 ret = sqlite3_last_insert_rowid(_db);
    _isExecutingStatement = NO;
    return ret;
}
- (int)changes{
    if (_isExecutingStatement) {
        [self warnInUse];
        return 0;
    }
    _isExecutingStatement = YES;
    int changes = sqlite3_changes(_db);
    _isExecutingStatement = NO;
    return changes;
}
#pragma mark --- sql cation
- (void)bindObject:(id)obj toColumn:(int)idx inStatement:(sqlite3_stmt*)pStmt{
    if ((!obj) || (NSNull *)obj == [NSNull null]) {
        sqlite3_bind_null(pStmt, idx);
    }else if ([obj isKindOfClass:[NSData class]]){
        const void *byte = [obj bytes];
        if (!byte) {
            byte = "";
        }
        sqlite3_bind_blob(pStmt, idx, byte, (int)[obj length], SQLITE_STATIC);
    }else if ([obj isKindOfClass:[NSDate class]]){
        if ([self hasDateFormatter]) {
            sqlite3_bind_text(pStmt, idx, [[self stringFromDate:obj] UTF8String], -1, SQLITE_STATIC);
        }else{
            sqlite3_bind_double(pStmt, idx, [obj timeIntervalSince1970]);
        }
    }else if ([obj isKindOfClass:[NSNumber class]]){
       ///比较类型编码的字符
        if ((strcmp([obj objCType], @encode(char))) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj charValue]);
        }else if ((strcmp([obj objCType], @encode(unsigned char)) == 0)){
            sqlite3_bind_int(pStmt, idx, [obj unsignedCharValue]);
        }else if ((strcmp([obj objCType], @encode(short)) == 0)){
            sqlite3_bind_int(pStmt, idx, [obj shortValue]);
        }else if ((strcmp([obj objCType], @encode(unsigned short)) == 0)){
            sqlite3_bind_int(pStmt, idx, [obj unsignedShortValue]);
        }else if ((strcmp([obj objCType], @encode(int)) == 0)){
            sqlite3_bind_int(pStmt, idx, [obj intValue]);
        }else if ((strcmp([obj objCType], @encode(unsigned int)) == 0)){
            sqlite3_bind_int(pStmt, idx, [obj unsignedIntValue]);
        }else if ((strcmp([obj objCType], @encode(long)) == 0)){
            sqlite3_bind_int64(pStmt, idx, [obj longValue]);
        }else if (strcmp([obj objCType], @encode(unsigned long)) == 0){
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongValue]);
        }else if (strcmp([obj objCType], @encode(long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, [obj longLongValue]);
        } else if (strcmp([obj objCType], @encode(unsigned long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongLongValue]);
        } else if (strcmp([obj objCType], @encode(float)) == 0) {
            sqlite3_bind_double(pStmt, idx, [obj floatValue]);
        }else if (strcmp([obj objCType], @encode(double)) == 0) {
            sqlite3_bind_double(pStmt, idx, [obj doubleValue]);
        }else if (strcmp([obj objCType], @encode(BOOL)) == 0) {
            sqlite3_bind_int(pStmt, idx, ([obj boolValue] ? 1 : 0));
        }else {
            sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
        }
    } else {
        sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
    }
}


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
#pragma mark --- 查询
- (ResultSet *)executeQuery:(NSString *)sql withParameterDictionary:(NSDictionary *)arguments{
    return [self executeQuery:sql withArgumentsInArray:nil orDictionary:arguments orVAList:nil];
}
- (ResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args{
    if (![self databaseExists]) {
        return 0x00;
    }
    if (_isExecutingStatement) {
        [self warnInUse];
        return 0x00;
    }
    
    int rc = 0x00;
    sqlite3_stmt *pstm = 0x00;
    Statement *statement = 0x00;
    ResultSet *result = 0x00;
    
    if (_traceExection && sql) {
        NSLog(@"traceExection %@ %@",self,sql);
    }
    
    if (_shouldCacheStatements) {
        statement = [self cacheStatementForQuery:sql];
        pstm = statement ? [statement statement] : 0x00;
        [statement reset];
    }
    if (!pstm) {
        rc = sqlite3_prepare(_db, [sql UTF8String], -1, &pstm, 0);
        if (rc != SQLITE_OK) {
            if (_logsErrors) {
                NSLog(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                NSLog(@"DB Query: %@", sql);
                NSLog(@"DB Path: %@", _databasePath);
            }
            if (_crashOnErrors) {
                NSAssert(false, @"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                abort();
            }
            
            sqlite3_finalize(pstm);
            _isExecutingStatement = NO;
            return nil;
        }
    }
    
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pstm);
    
    if (dictionaryArgs) {
        for (NSString *key in [dictionaryArgs allKeys]) {
            ///key 前添加冒号
            NSString *parameterName = [NSString stringWithFormat:@":%@",key];
            if (_traceExection) {
                NSLog(@"%@ = %@",parameterName,[dictionaryArgs objectForKey:key]);
            }
            
            int nameIdx = sqlite3_bind_parameter_index(pstm, [parameterName UTF8String]);
            DBRelease(parameterName);
            
            if (nameIdx > 0) {
                [self bindObject:[dictionaryArgs objectForKey:key] toColumn:nameIdx inStatement:pstm];
                nameIdx ++ ;
            }else{
                NSLog(@"Could not find index for %@",key);
            }
        }
    }else{
        while (idx < queryCount) {
            if (arrayArgs && idx < (int)arrayArgs.count) {
                obj = arrayArgs[idx];
            }else if (args){
                obj = va_arg(args, id);
            }else{
                break;
            }
            if (_traceExection) {
                if ([obj isKindOfClass:[NSData class]]) {
                    NSLog(@"data: %ld bytes", (unsigned long)[(NSData*)obj length]);
                }
                else {
                    NSLog(@"obj: %@", obj);
                }
            }
            idx ++ ;
            [self bindObject:obj toColumn:idx inStatement:pstm];
        }
    }
    if (idx != queryCount) {
        NSLog(@"Error: the bind count is not correct for the # of variables (executeQuery)");
        sqlite3_finalize(pstm);
        _isExecutingStatement = NO;
        return nil;
    }
    
    DBRetain(statement);
    if (!statement) {
        statement = [[Statement alloc] init];
        [statement setStatement:pstm];
        if (_shouldCacheStatements && sql) {
            [self setCachedStatement:statement forQuery:sql];
        }
    }
    
    result = [ResultSet resultSetWithStatement:statement usingParentDatabase:self];
    [result setQuery:sql];
    
    NSValue *openResultSet = [NSValue valueWithNonretainedObject:result];
    [_openResultSets addObject:openResultSet];
    [statement setUseCount:[statement useCount] + 1];
    DBRelease(statement);
    _isExecutingStatement = NO;
    return result;
}
- (ResultSet *)executeQuery:(NSString *)sql, ...{
    va_list args;
    va_start(args, sql);
    id result = [self executeQuery:sql withArgumentsInArray:nil orDictionary:nil orVAList:args];
    va_start(args, sql);
    return result;
}
- (ResultSet *)executeQueryWithFormat:(NSString *)format, ...{
    va_list args;
    
    va_start(args, format);
    ///format转成sql
    NSMutableString *sql = [NSMutableString stringWithCapacity:format.length];
    NSMutableArray *arguments = [NSMutableArray new];
    [self extractSQL:format argumentsList:args intoString:sql arguments:arguments];
    va_end(args);
    return [self executeQuery:sql withArgumentsInArray:arguments];
}
- (ResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arguments{
    return [self executeQuery:sql withArgumentsInArray:arguments orDictionary:nil orVAList:nil];
}
- (ResultSet *)executeQuery:(NSString *)sql values:(NSArray *)values error:(NSError *__autoreleasing  _Nullable *)error{
    ResultSet *res = [self executeQuery:sql withArgumentsInArray:values orDictionary:nil orVAList:nil];
    if (!res && error) {
        *error = [self lastError];
    }
    return res;
}
- (ResultSet *)executeQuery:(NSString *)sql withVAList:(va_list)args{
    return [self executeQuery:sql withArgumentsInArray:nil orDictionary:nil orVAList:args];
}

#pragma mark 增删改
- (BOOL)executeUpdate:(NSString *)sql error:(NSError *__autoreleasing  _Nullable *)outErr withArgumentsInArray:(NSArray *)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args{
    if (![self databaseExists]) {
        return NO;
    }
    if (_isExecutingStatement) {
        [self warnInUse];
        return NO;
    }
    
    _isExecutingStatement = YES;
    int rc = 0x00;
    sqlite3_stmt *pStmt = 0x00;
    Statement *cacheStatement = 0x00;
    
    if (_traceExection && sql) {
        NSLog(@"tractExection %@ %@",self,sql);
    }
    
    if (_shouldCacheStatements) {
        cacheStatement = [self cacheStatementForQuery:sql];
        pStmt = cacheStatement ? [cacheStatement statement] : 0x00;
        [cacheStatement reset];
    }
    if (!pStmt) {
        rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
        if (rc != SQLITE_OK) {
            if (_logsErrors) {
                NSLog(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                NSLog(@"DB Query: %@", sql);
                NSLog(@"DB Path: %@", _databasePath);
            }
            
            if (_crashOnErrors) {
                NSAssert(false, @"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                abort();
            }
            if (outErr) {
                *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
            }
            sqlite3_finalize(pStmt);
            _isExecutingStatement = NO;
            return NO;
        }
    }
    id obj = 0x00;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt);
    
    if (dictionaryArgs) {
        for (NSString *key in dictionaryArgs.allKeys) {
            NSString *parmerName = [NSString stringWithFormat:@":%@",key];
            if (_traceExection) {
                NSLog(@"%@ = %@",parmerName,[dictionaryArgs objectForKey:key]);
            }
            int nameIndex = sqlite3_bind_parameter_index(pStmt, [parmerName UTF8String]);
            DBRelease(parnerName);
            
            if (nameIndex > 0) {
                [self bindObject:[dictionaryArgs objectForKey:key] toColumn:nameIndex inStatement:pStmt];
                nameIndex ++;
            }else{
                NSString *message = [NSString stringWithFormat:@"could not find index  for %@",key];
                if (_logsErrors) {
                    NSLog(@"%@",message);
                }
                if (outErr) {
                    *outErr = [self errorWithMessage:message];
                }
            }
        }
    }else{
        while (idx < queryCount) {
            if (arrayArgs && idx < (int)arrayArgs.count) {
                obj = [arrayArgs objectAtIndex:(NSInteger)idx];
            }else if (args){
                obj = va_arg(args, id);
            }else{
                break;
            }
            if (_traceExection) {
                if ([obj isKindOfClass:[NSData class]]) {
                    NSLog(@"data : %ld butes",((NSData *)obj).length);
                }else{
                    NSLog(@"obj = %@",obj);
                }
            }
            idx++;
            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }
    
    if (idx != queryCount) {
        
        NSString *message = [NSString stringWithFormat:@"Error: the bind count (%d) is not correct for the # of variables in the query (%d) (%@) (executeUpdate)", idx, queryCount, sql];
        if (_traceExection) {
            NSLog(@"%@",message);
        }
        
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }
        _isExecutingStatement = NO;
        sqlite3_finalize(pStmt);
        return NO;
    }
    rc = sqlite3_step(pStmt);
    
    if (rc == SQLITE_DONE) {
    }else if (rc == SQLITE_INTERRUPT){
        if (_logsErrors) {
            NSLog(@"Error calling sqlite3_step. Query was interrupted (%d: %s) SQLITE_INTERRUPT", rc, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    }else if (rc == SQLITE_ROW){
        NSString *message = [NSString stringWithFormat:@"A executeUpdate is being called with a query string '%@'", sql];
        if (_logsErrors) {
            NSLog(@"%@", message);
            NSLog(@"DB Query: %@", sql);
        }
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }
    }else {
        if (outErr) {
            *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
        }
        
        if (SQLITE_ERROR == rc) {
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_ERROR", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
        else if (SQLITE_MISUSE == rc) {
            // uh oh.
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_MISUSE", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
        else {
            // wtf?
            if (_logsErrors) {
                NSLog(@"Unknown error calling sqlite3_step (%d: %s) eu", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
    }
    
    if (_shouldCacheStatements && !cacheStatement) {
        cacheStatement = [[Statement alloc] init];
        [cacheStatement setStatement:pStmt];
        [self setCachedStatement:cacheStatement forQuery:sql];
        DBRelease(cacheStetement);
    }
    int closeErrorCode;
    if (cacheStatement) {
        [cacheStatement setUseCount:[cacheStatement useCount] + 1];
        closeErrorCode = sqlite3_reset(pStmt);
    }else{
        closeErrorCode = sqlite3_finalize(pStmt);
    }
    if (closeErrorCode != SQLITE_OK) {
        if (_logsErrors) {
            NSLog(@"Unknown error finalizing or resetting statement (%d: %s)", closeErrorCode, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    }
    _isExecutingStatement = NO;
    return (rc == SQLITE_DONE || rc == SQLITE_OK);
}
- (BOOL)executeUpdate:(NSString *)sql, ...{
    va_list args;
    va_start(args, sql);
//    id obj;
//    while ((obj = va_arg(args, id))) {
//        NSLog(@"obj = %@",obj);
//    }
    BOOL result = [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:nil orVAList:args];
    va_end(args);
    return result;
}
- (BOOL)executeUpdate:(NSString *)sql withArgumentsInArray:(NSArray *)arguments{
    return [self executeUpdate:sql error:nil withArgumentsInArray:arguments orDictionary:nil orVAList:nil];
}
- (BOOL)executeUpdate:(NSString *)sql values:(NSArray *)values error:(NSError *__autoreleasing  _Nullable *)error{
    return [self executeUpdate:sql error:error withArgumentsInArray:values orDictionary:nil orVAList:nil];
}
- (BOOL)executeUpdate:(NSString *)sql withParameterDictionary:(NSDictionary *)arguments{
    return [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:arguments orVAList:nil];
}
- (BOOL)executeUpdate:(NSString *)sql withVAList:(va_list)args{
    return [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:nil orVAList:args];
}
- (BOOL)executeUpdateWithFormat:(NSString *)format, ...{
    va_list args;
    va_start(args, format);
    NSMutableString *sql = [NSMutableString stringWithCapacity:format.length];
    NSMutableArray *argments = [NSMutableArray new];
    [self extractSQL:format argumentsList:args intoString:sql arguments:argments];
    va_end(args);
    bool result = [self executeUpdate:sql withArgumentsInArray:argments];
    return result;
}
- (BOOL)executeUpdate:(NSString *)sql withErrorAndBindings:(NSError *__autoreleasing  _Nullable *)outErr, ...{
    va_list args ;
    va_start(args, outErr);
    BOOL result = [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:args];
    va_end(args);
    return result;
}
- (BOOL)executeStatements:(NSString *)sql{
    return [self executeStatements:sql withResultBlock:nil];
}
- (BOOL)executeStatements:(NSString *)sql withResultBlock:(__attribute__((noescape))DBEcecuteStatementsCallBackBlock)block{
    int rc ;
    char *errorMsg;
    
    rc = sqlite3_exec([self sqliteHandle], sql.UTF8String, block ? DBExecuteBulkSQLCallBack : nil, (__bridge void *)block, &errorMsg);
    if (errorMsg && [self logsErrors]) {
        NSLog(@"Error inserting batch: %s", errorMsg);
        sqlite3_free(errorMsg);
    }
    return rc == SQLITE_OK;
}
///sqlite execute 回调
int DBExecuteBulkSQLCallBack(void *theBlockAsVoid,int columns,char **values,char **names);
int DBExecuteBulkSQLCallBack(void *theBlockAsVoid,int columns,char **values,char **names){
    if (!theBlockAsVoid) {
        return SQLITE_OK;
    }
    int (^executeCallBaclBlock)(NSDictionary *result) = (__bridge int (^)(NSDictionary *__strong))(theBlockAsVoid);
    
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithCapacity:(NSUInteger)columns];
    
    for (int i = 0; i < columns; i++) {
        NSString *key = [NSString stringWithUTF8String:names[i]];
        id value = values[i] ? [NSString stringWithUTF8String:values[i]] : [NSNull null];
        [dictionary setObject:value forKey:key];
    }
    return executeCallBaclBlock(dictionary);
}

#pragma mark --- mark 事务
- (BOOL)rollback{
    BOOL res = [self executeUpdate:@"rollback transaction"];
    if (res) {
        _isInTransaction = NO;
    }
    return res;
}
- (BOOL)commit{
    BOOL res = [self executeUpdate:@"commit transaction"];
    if (res) {
        _isInTransaction = NO;
    }
    return res;
}
///开始延迟执行事务
- (BOOL)beginDeferredTransaction{
    BOOL res = [self executeUpdate:@"begin deferred transaction"];
    if (res) {
        _isInTransaction = NO;
    }
    return res;
}
///立即执行事务
- (BOOL)beginTransaction{
    BOOL res = [self executeUpdate:@"begin exclusive transaction"];
    if (res) {
        _isInTransaction = NO;
    }
    return res;
}
- (BOOL)interrupt{
    if (_db) {
        sqlite3_interrupt([self sqliteHandle]);
        return YES;
    }
    return NO;
}
static NSString *DBEscapeSavePointName(NSString *saveName){
    return [saveName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
}
///保存事务点
- (BOOL)startSavePointWithName:(NSString *)name error:(NSError *__autoreleasing  _Nullable *)outErr{
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);
    NSString *sql = [NSString stringWithFormat:@"savepoint '%@';",DBEscapeSavePointName(name)];
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString *errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}
///释放事务点
- (BOOL)releaseSavePointWithName:(NSString *)name error:(NSError *__autoreleasing  _Nullable *)outErr{
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);
    NSString *sql = [NSString stringWithFormat:@"release savepoint '%@';",DBEscapeSavePointName(name)];
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString *errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}
///回滚到某一点
- (BOOL)rollbackToSavePointWithName:(NSString *)name error:(NSError *__autoreleasing  _Nullable *)outErr{
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);
    NSString *sql = [NSString stringWithFormat:@"rollback transaction to savepoint '%@'",DBEscapeSavePointName(name)];
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString *errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}
/// I do not konw what is the use 
- (NSError *)inSavePoint:(__attribute__((noescape)) void (^)(BOOL * _Nonnull))block{
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIndex = 0;
    NSString *name = [NSString stringWithFormat:@"dbSavePoint%ld",savePointIndex++];
    BOOL shouldRollBack = NO;
    NSError *error = 0x00;
    if (![self startSavePointWithName:name error:&error]) {
        return error;
    }
    if (block) {
        block(&shouldRollBack);
    }
    if (shouldRollBack) {
        [self rollbackToSavePointWithName:name error:&error];
    }
    [self releaseSavePointWithName:name error:&error];
    return error;
#else
    NSString *errorMessage = NSLocalizedString(@"Save point functions require SQLite 3.7", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"FMDatabase" code:0 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
#endif
}
#pragma mark cache statement
- (BOOL)shouldCacheStatements{
    return _shouldCacheStatements;
}
- (void)setShouldCacheStatements:(BOOL)shouldCacheStatements{
    _shouldCacheStatements = shouldCacheStatements;
    if (_shouldCacheStatements && !_cachedStatements) {
        [self setCachedStatements:[NSMutableDictionary new]];
    }

    if (!_shouldCacheStatements) {
        [self setCachedStatements:nil];
    }
}

#pragma mark  sql Function  CallBack
void DBBlockSqliteCallBackFunction(sqlite3_context *context, int argc,sqlite3_value **argv);

void DBBlockSqliteCallBackFunction(sqlite3_context *context, int argc,sqlite3_value **argv){
#if ! __has_feature(objc_arc)
    void (^block)(sqlite3_context *context, int argc,sqlite3_value **argv) = (id)sqlite3_user_data(context);
#else
    void (^block)(sqlite3_context *context, int argc,sqlite3_value **argv) = (__bridge id)sqlite3_user_data(context);
#endif
    if (block) {
        @autoreleasepool {
            block(context,argc,argv);
        }
    }
}
/**
 添加sql 函数
 @param name 函数名
 @param arguments 参数
 @param block 函数回调
 */
- (void)makeFunctionNamed:(NSString *)name arguments:(int)arguments block:(void (^)(void * _Nonnull, int, void * _Nonnull * _Nonnull))block{
    if (_openResultSets) {
        _openResultSets = [NSMutableSet new];
    }
    id b = DBReturnAutoreleased([block copy]);
    if (b) [_openResultSets addObject:b];
    
#if !__has_feature(objc_arc)
    sqlite3_create_function([self sqliteHandle], [name UTF8String], arguments, SQLITE_UTF8, (void *)b, &DBBlockSqliteCallBackFunction, 0x00, 0x00);
#else
    sqlite3_create_function([self sqliteHandle], [name UTF8String], arguments, SQLITE_UTF8, (__bridge void*)b, &DBBlockSqliteCallBackFunction, 0x00, 0x00);
#endif
    
}
#pragma mark ---- custome function  value type
/*
 自定义函数参数类型获取和设置
 自定义函数 回调时会有一个上下文 context 和参数集合  自定义操作之后通过 resultTypeInContext 重新设置参数
 */

//获取自定义函数类型
- (SqliteValueType)valueType:(void *)argv{
    return sqlite3_value_type(argv);
}
- (int)valueInt:(void *)value{
    return sqlite3_value_int(value);
}
- (double)valueDouble:(void *)value{
    return sqlite3_value_double(value);
}
- (NSData *)valueData:(void *)value{
    const void* bytes = sqlite3_value_blob(value);
    int length = sqlite3_value_bytes(value);
    return bytes ? [NSData dataWithBytes:bytes length:length] : nil;
}
- (NSString *)valueString:(void *)value{
    const char *str = (const char *)sqlite3_value_text(value);
    return str ? [NSString stringWithUTF8String:str] : nil;
}
- (long long)valueLong:(void *)value{
    return sqlite3_value_int64(value);
}
///重新设置自定义函数的参数
- (void)resultNullInContext:(void *)context{
    sqlite3_result_null(context);
}
- (void)resultInt:(int)value context:(void *)context{
    sqlite3_result_int(context, value);
}
- (void)resultLong:(long long)value context:(void *)context{
    sqlite3_result_int64(context, value);
}
- (void)resultDouble:(double)value context:(void *)context{
    sqlite3_result_double(context, value);
}
- (void)resultData:(NSData *)data context:(void *)context{
    sqlite3_result_blob(context, data.bytes, (int)data.length, SQLITE_TRANSIENT);
}
- (void)resultString:(NSString *)value context:(void *)context{
    sqlite3_result_text(context, value.UTF8String, (int)value.length, SQLITE_TRANSIENT);
}
- (void)resultError:(NSString *)error context:(void *)context{
    sqlite3_result_error(context, [error UTF8String], -1);
}
- (void)resultErrorCode:(int)errorCode context:(void *)context{
    sqlite3_result_error_code(context, errorCode);
}
- (void)resultErrorNoMemoryInContext:(void *)context{
    sqlite3_result_error_nomem(context);
}
- (void)resultErrorTooBigInContext:(void *)context{
    sqlite3_result_error_toobig(context);
}
@end

@implementation Statement
#if !__has_feature(objc_arc)
- (void)finalize {
    [self close];
    [super finalize];
}
#endif

- (void)dealloc{
    [self close];
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}
- (void)close {
    if (_statement) {
        sqlite3_finalize(_statement);
        _statement = 0x00;
    }
    _inUse = NO;
}

- (void)reset {
    if (_statement) {
        sqlite3_reset(_statement);
    }
    _inUse = NO;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %ld hit(s) for query %@", [super description], _useCount, _query];
}

@end

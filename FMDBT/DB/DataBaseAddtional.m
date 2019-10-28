//
//  DataBaseAddtional.m
//  FMDBT
//
//  Created by hqz on 2019/6/21.
//  Copyright © 2019 8km. All rights reserved.
//

#import "DataBaseAddtional.h"
#import <sqlite3.h>


@interface DataBase ()

- (ResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray * _Nullable)arrayArgs orDictionary:(NSDictionary * _Nullable)dictionaryArgs orVAList:(va_list)args;

@end

#define RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(type,sel)                                   \
va_list args;                                   \
va_start(args, query);                                   \
ResultSet *result = [self executeQuery:query withArgumentsInArray:nil orDictionary:nil orVAList:args];                                    \
if (![result next]) return (type)0;                                    \
va_end(args);                                      \
type ret = [result sel:0];                                    \
[result close];                                    \
[result setParentDB:nil];                                    \
return ret;





@implementation DataBase (DataBaseAddtional)

- (NSString *)stringForQuery:(NSString*)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(NSString *, stringForColumnIndex);
}
- (int)intForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(int, intForColumnIndex);
}

- (long)longForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(long , longForColumnIndex);
}
- (BOOL)boolForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(BOOL, boolForColumnIndex);
}
- (double)doubleForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(double, doubleForColumnIndex);
}
- (NSData *)dataForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(NSData *, dataForColumnIndex);
}
- (NSDate *)dateForQuery:(NSString *)query, ...{
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(NSDate *, dateForColumnIndex);
}
- (BOOL)tableExists:(NSString *)tableName{
    tableName = [tableName lowercaseString];
    ResultSet *resultSet = [self executeQuery:@"select [sql] from sqlite_master where [type] = 'table' and lower(name) = ?",tableName];
    BOOL result = [resultSet next];
    [resultSet close];
    return result;
}
- (ResultSet *)getSchema{
    ResultSet *rs = [self executeQuery:@"SELECT type, name, tbl_name, rootpage, sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, type DESC, name"];
    return rs;
}
- (ResultSet *)getTableSchema:(NSString *)tableName{
    ResultSet *rs = [self executeQuery:[NSString stringWithFormat: @"pragma table_info('%@')", tableName]];
    return rs;
}

- (BOOL)columnExists:(NSString *)columnName inTableWithName:(NSString *)tableName{
    BOOL returnBool = NO;
    tableName = [tableName lowercaseString];
    columnName = [columnName lowercaseString];
    ResultSet *res = [self getTableSchema:tableName];
    while ([res next]) {
        if ([[res stringForColumn:@"name"] isEqualToString:columnName]) {
            returnBool = YES;
            break;
        }
    }
    return returnBool;
}
- (uint32_t)applicationID{
#if SQLITE_VERSION_NUMBER >= 3007017
    uint32_t result = 0;
    ResultSet *resSet = [self executeQuery:@"pragma application_id"];
    if ([resSet next]) {
        result = (uint32_t)[resSet longLongIntForColumnIndex:0];
    }
    [resSet close];
    return result;
#else
    NSString *errorMessage = NSLocalizedString(@"Application ID functions require SQLite 3.7.17", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return 0;
#endif
}
- (void)setApplicationID:(uint32_t)applicationID{
#if SQLITE_VERSION_NUMBER >= 3007017
    NSString *query = [NSString stringWithFormat:@"pragma application_id=%d", applicationID];
    ResultSet *rs = [self executeQuery:query];
    [rs next];
    [rs close];
#else
    NSString *errorMessage = NSLocalizedString(@"Application ID functions require SQLite 3.7.17", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
#endif
}
- (uint32_t)userVersion {
    uint32_t r = 0;
    
    ResultSet *rs = [self executeQuery:@"pragma user_version"];
    
    if ([rs next]) {
        r = (uint32_t)[rs longLongIntForColumnIndex:0];
    }
    
    [rs close];
    return r;
}

- (void)setUserVersion:(uint32_t)version {
    NSString *query = [NSString stringWithFormat:@"pragma user_version = %d", version];
    ResultSet *rs = [self executeQuery:query];
    [rs next];
    [rs close];
}
- (BOOL)validateSQL:(NSString *)sql error:(NSError *__autoreleasing  _Nullable *)error{
    sqlite3_stmt *stmt = NULL;
    BOOL valudationSucceed = YES;
    int rc = sqlite3_prepare([self sqliteHandle], sql.UTF8String, -1, &stmt, 0);
    if (rc != SQLITE_OK) {
        valudationSucceed = NO;
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:[self lastErrorCode] userInfo:[NSDictionary dictionaryWithObject:[self lastErrorMessage] forKey:NSLocalizedDescriptionKey]];
        }
    }
    sqlite3_finalize(stmt);
    return valudationSucceed;
}

@end


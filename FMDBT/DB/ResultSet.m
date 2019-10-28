//
//  ResultSet.m
//  FMDBT
//
//  Created by hqz on 2019/5/28.
//  Copyright © 2019 8km. All rights reserved.
//

#import "ResultSet.h"
#import "DataBase.h"
#import "unistd.h"

#if FMDB_SQLITE_STANDALONE
#import <sqlite3/sqlite3.h>
#else
#import <sqlite3.h>
#endif


@interface DataBase ()

- (void)resultSetDidClose:(ResultSet *)resultSet;

@end

@implementation ResultSet{
    ///列的index 对应的列名
    NSMutableDictionary *_columnNameToIndexMap;
}
+ (instancetype)resultSetWithStatement:(Statement *)statement usingParentDatabase:(DataBase *)aDB{
    ResultSet *resultSet = [[ResultSet alloc] init];
    [resultSet setStatement:statement];
    [resultSet setParentDB:aDB];
    NSParameterAssert(![statement inUse]);
    
    [statement setInUse:YES];
    return DBReturnAutoreleased(resultSet);
}
#if ! __has_feature(objc_arc)
- (void)finalize {
    [self close];
    [super finalize];
}
#endif

- (void)dealloc{
    [self close];
    DBRelease(_query);
    _query = nil;
    DBRelease(_columnNameToIndexMap);
    _columnNameToIndexMap = nil;
    
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}
- (void)close{
    [_statement reset];
    DBRelease(_statement);
    _statement = nil;
    
    [_parentDB resultSetDidClose:self];
    _parentDB = nil;
}
- (int)columnCount{
    return sqlite3_column_count([_statement statement]);
}
- (NSMutableDictionary *)columnNameToIndexMap{
    if (!_columnNameToIndexMap) {
        int columnCount = sqlite3_column_count([_statement statement]);
        _columnNameToIndexMap = [[NSMutableDictionary alloc] initWithCapacity:columnCount];
        int columnIndex = 0;
        for (columnIndex = 0; columnIndex < columnCount; columnIndex++) {
            [_columnNameToIndexMap setObject:[NSNumber numberWithInt:columnIndex] forKey:[NSString stringWithUTF8String:sqlite3_column_name([_statement statement], columnIndex)]];
        }
    }
    return _columnNameToIndexMap;
}
- (void)kvcMagic:(id)object{
    int columCount = sqlite3_column_count([_statement statement]);
    int columnIndex = 0;
    for (columnIndex = 0; columnIndex < columCount; columnIndex++) {
        const char *c = (const char *) sqlite3_column_text([_statement statement], columnIndex);
        if (c) {
            NSString *value = [NSString stringWithUTF8String:c];
            NSString *key = [NSString stringWithUTF8String:sqlite3_column_name([_statement statement], columnIndex)];
            if (key && value) {
                [object setValue:value forKey:key];
            }
        }
    }
}
- (NSDictionary *)resultDictionary{
    NSUInteger num_cols = (NSUInteger)sqlite3_data_count([_statement statement]);
    
    if (num_cols > 0) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:num_cols];
        int columnIndex = 0;
        int columnCount = sqlite3_column_count([_statement statement]);
        for (columnIndex = 0; columnIndex < columnCount; columnIndex++) {
            NSString *name = [NSString stringWithUTF8String:sqlite3_column_name([_statement statement], columnIndex)];
            id value = [self objectForColumnIndex:columnIndex];
            if (value && name) {
                [dic setObject:value forKey:name];
            }
        }
        return dic;
    }else{
        return nil;
    }
}
- (BOOL)next {
    return [self nextWithError:nil];
}

- (BOOL)nextWithError:(NSError **)outErr {
    
    int rc = sqlite3_step([_statement statement]);
    
    if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
        NSLog(@"%s:%d Database busy (%@)", __FUNCTION__, __LINE__, [_parentDB databasePath]);
        NSLog(@"Database busy");
        if (outErr) {
            *outErr = [_parentDB lastError];
        }
    }
    else if (SQLITE_DONE == rc || SQLITE_ROW == rc) {
        // all is well, let's return.
    }
    else if (SQLITE_ERROR == rc) {
        NSLog(@"Error calling sqlite3_step (%d: %s) rs", rc, sqlite3_errmsg([_parentDB sqliteHandle]));
        if (outErr) {
            *outErr = [_parentDB lastError];
        }
    }
    else if (SQLITE_MISUSE == rc) {
        // uh oh.
        NSLog(@"Error calling sqlite3_step (%d: %s) rs", rc, sqlite3_errmsg([_parentDB sqliteHandle]));
        if (outErr) {
            if (_parentDB) {
                *outErr = [_parentDB lastError];
            }
            else {
                // If 'next' or 'nextWithError' is called after the result set is closed,
                // we need to return the appropriate error.
                NSDictionary* errorMessage = [NSDictionary dictionaryWithObject:@"parentDB does not exist" forKey:NSLocalizedDescriptionKey];
                *outErr = [NSError errorWithDomain:@"FMDatabase" code:SQLITE_MISUSE userInfo:errorMessage];
            }
            
        }
    }
    else {
        // wtf?
        NSLog(@"Unknown error calling sqlite3_step (%d: %s) rs", rc, sqlite3_errmsg([_parentDB sqliteHandle]));
        if (outErr) {
            *outErr = [_parentDB lastError];
        }
    }
    
    
    if (rc != SQLITE_ROW) {
        [self close];
    }
    
    return (rc == SQLITE_ROW);
}
- (BOOL)hasAnotherRow {
    return sqlite3_errcode([_parentDB sqliteHandle]) == SQLITE_ROW;
}
#pragma mark  列的index
- (int)columnIndexForName:(NSString *)columnName{
    columnName = [columnName lowercaseString];
    NSNumber *b = [[self columnNameToIndexMap] objectForKey:columnName];
    if (b) {
        return [b intValue];
    }
    return -1;
}
#pragma mark ---- column value
- (int)intForColumn:(NSString *)columnName{
    return [self intForColumnIndex:[self columnIndexForName:columnName]];
}
- (int)intForColumnIndex:(int)columnIdx{
    return sqlite3_column_int([_statement statement], columnIdx);
}
- (long)longForColumn:(NSString *)columnName{
    return [self longLongIntForColumnIndex:[self columnIndexForName:columnName]];
}
- (long)longForColumnIndex:(int)columnIdx{
    return sqlite3_column_int64([_statement statement], columnIdx);
}
- (long long)longLongIntForColumn:(NSString *)columnName{
    return [self longLongIntForColumnIndex:[self columnIndexForName:columnName]];
}
- (long long)longLongIntForColumnIndex:(int)columnIdx{
    return sqlite3_column_int64([_statement statement], columnIdx);
}
- (unsigned long long int)unsignedLongLongIntForColumn:(NSString*)columnName {
    return [self unsignedLongLongIntForColumnIndex:[self columnIndexForName:columnName]];
}

- (unsigned long long int)unsignedLongLongIntForColumnIndex:(int)columnIdx {
    return (unsigned long long int)[self longLongIntForColumnIndex:columnIdx];
}
- (BOOL)boolForColumn:(NSString*)columnName {
    return [self boolForColumnIndex:[self columnIndexForName:columnName]];
}

- (BOOL)boolForColumnIndex:(int)columnIdx {
    return ([self intForColumnIndex:columnIdx] != 0);
}

- (double)doubleForColumn:(NSString*)columnName {
    return [self doubleForColumnIndex:[self columnIndexForName:columnName]];
}

- (double)doubleForColumnIndex:(int)columnIdx {
    return sqlite3_column_double([_statement statement], columnIdx);
}
- (NSString *)stringForColumn:(NSString *)columnName{
    return [self stringForColumnIndex:[self columnIndexForName:columnName]];
}
- (NSString *)stringForColumnIndex:(int)columnIdx{
    if (sqlite3_column_type([_statement statement], columnIdx) == SQLITE_NULL || (columnIdx < 0 || columnIdx > sqlite3_column_count([_statement statement]))) {
        return nil;
    }
    const char *c = (const char *) sqlite3_column_text([_statement statement], columnIdx);
    if (!c) {
        return nil;
    }
    return [NSString stringWithUTF8String:c];
}
- (NSDate *)dateForColumn:(NSString *)columnName{
    return [self dateForColumnIndex:[self columnIndexForName:columnName]];
}
- (NSDate *)dateForColumnIndex:(int)columnIdx{
    if (sqlite3_column_type([_statement statement], columnIdx) == SQLITE_NULL || (columnIdx < 0 || columnIdx > sqlite3_column_count([_statement statement]))) {
        return nil;
    }
    return [_parentDB hasDateFormatter] ? [_parentDB dateFromString:[self stringForColumnIndex:columnIdx]] : [NSDate dateWithTimeIntervalSince1970:[self doubleForColumnIndex:columnIdx]];
}
- (NSData *)dataForColumn:(NSString *)columnName{
    return [self dataForColumnIndex:[self columnIndexForName:columnName]];
}
- (NSData *)dataForColumnIndex:(int)columnIdx{
    if (sqlite3_column_type([_statement statement], columnIdx) == SQLITE_NULL || (columnIdx < 0 || columnIdx > sqlite3_column_count([_statement statement]))) {
        return nil;
    }
    const char *buffrtData = sqlite3_column_blob([_statement statement], columnIdx);
    int dataSize = sqlite3_column_bytes([_statement statement], columnIdx);
    if (buffrtData == NULL) {
        return nil;
    }
    return [NSData dataWithBytes:(const void *)buffrtData length:(NSUInteger)dataSize];
}
- (NSData *)dataNoCopyForColumn:(NSString *)columnName{
    return [self dataNoCopyForColumnIndex:[self columnIndexForName:columnName]];
}
- (NSData *)dataNoCopyForColumnIndex:(int)columnIdx{
    if (sqlite3_column_type([_statement statement], columnIdx) == SQLITE_NULL || (columnIdx < 0 || columnIdx > sqlite3_column_count([_statement statement]))) {
        return nil;
    }
    const char *buffrtData = sqlite3_column_blob([_statement statement], columnIdx);
    int dataSize = sqlite3_column_bytes([_statement statement], columnIdx);
    if (buffrtData == NULL) {
        return nil;
    }
    return [NSData dataWithBytesNoCopy:(void *)buffrtData length:(NSUInteger)dataSize freeWhenDone:YES];
}

- (BOOL)columnIndexIsNull:(int)columnIdx {
    return sqlite3_column_type([_statement statement], columnIdx) == SQLITE_NULL;
}

- (BOOL)columnIsNull:(NSString*)columnName {
    return [self columnIndexIsNull:[self columnIndexForName:columnName]];
}

- (const unsigned char *)UTF8StringForColumnIndex:(int)columnIdx {
    
    if (sqlite3_column_type([_statement statement], columnIdx) == SQLITE_NULL || (columnIdx < 0) || columnIdx >= sqlite3_column_count([_statement statement])) {
        return nil;
    }
    
    return sqlite3_column_text([_statement statement], columnIdx);
}

- (const unsigned char *)UTF8StringForColumn:(NSString*)columnName {
    return [self UTF8StringForColumnIndex:[self columnIndexForName:columnName]];
}

- (const unsigned char *)UTF8StringForColumnName:(NSString*)columnName {
    return [self UTF8StringForColumn:columnName];
}
- (id)objectForColumn:(NSString *)columnName{
    return [self objectForColumnIndex:[self columnIndexForName:columnName]];
}

- (id)objectForColumnIndex:(int)columnIdx{
    if (columnIdx < 0 || columnIdx > sqlite3_column_count([_statement statement])) {
        return nil;
    }
    int columnType = sqlite3_column_type([_statement statement], columnIdx);
    id returnValye = nil;
    if (columnType == SQLITE_INTEGER) {
        returnValye = [NSNumber numberWithLongLong:[self longLongIntForColumnIndex:columnIdx]];
    }else if (columnType == SQLITE_FLOAT){
        returnValye = [NSNumber numberWithDouble:[self doubleForColumnIndex:columnIdx]];
    }else if (columnType == SQLITE_BLOB){
        returnValye = [self dataForColumnIndex:columnIdx];
    }else{
        returnValye = [self stringForColumnIndex:columnIdx];
    }
    if (returnValye == nil) {
        returnValye = [NSNull null];
    }
    return returnValye;
}
- (NSString *)columnNameForIndex:(int)columnIdx{
    return [NSString stringWithUTF8String:sqlite3_column_name([_statement statement], columnIdx)];
}
- (id)objectForKeyedSubscript:(NSString *)columnName{
   return [self objectForColumn:columnName];
}
- (id)objectAtIndexedSubscript:(int)columnIdx{
    return [self objectForColumnIndex:columnIdx];
}
@end


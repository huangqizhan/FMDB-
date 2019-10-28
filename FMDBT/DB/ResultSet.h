//
//  ResultSet.h
//  FMDBT
//
//  Created by hqz on 2019/5/28.
//  Copyright © 2019 8km. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


#ifndef __has_feature      // Optional.
#define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

#ifndef NS_RETURNS_NOT_RETAINED
#if __has_feature(attribute_ns_returns_not_retained)
#define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#else
#define NS_RETURNS_NOT_RETAINED
#endif
#endif

@class DataBase;
@class Statement;

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

NS_ASSUME_NONNULL_END

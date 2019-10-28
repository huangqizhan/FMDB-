//
//  DataBaseAddtional.h
//  FMDBT
//
//  Created by hqz on 2019/6/21.
//  Copyright © 2019 8km. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataBase.h"

NS_ASSUME_NONNULL_BEGIN

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


NS_ASSUME_NONNULL_END

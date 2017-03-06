//
//  UTAVideoURLService.h
//  UTALib
//
//  Created by David on 16/5/31.
//  Copyright © 2016年 UTA. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void (^UTAVideoURLServiceCompletion)(NSURL * _Nullable url, NSError * _Nullable error);

/*!
 *  视频地址解析服务
 *  支持内存缓存：
 *      解析过的视频地址不再解析；
 *      列表中已存在正在解析的地址，不解析，等待解析完后一并通知；
 */
@interface UTAVideoURLService : NSObject

/*!
 *  根据任意视频网页地址，解析出iOS移动设备适用的，视频地址；默认超时时间60s
 *
 *  @param link       原始链接
 *  @param completion 解析完成
 */
+ (void)resolveVideoURLWithOriginLink:(nonnull NSString *)link completion:(nonnull UTAVideoURLServiceCompletion)completion;

/*!
 *  根据任意视频网页地址，解析出iOS移动设备适用的，视频地址；默认超时时间60s
 *
 *  @param link       原始链接
 *  @param timeout    解析超时时间限制
 *  @param completion 解析完成
 */
+ (void)resolveVideoURLWithOriginLink:(nonnull NSString *)link timeout:(NSTimeInterval)timeout completion:(nonnull UTAVideoURLServiceCompletion)completion;

+ (void)cancelResolveWithOriginLink:(nonnull NSString *)link;

@end

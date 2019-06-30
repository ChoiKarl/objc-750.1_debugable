//
//  KLSubTest.m
//  Test
//
//  Created by karl on 2019/01/13.
//

#import "KLSubTest.h"

@implementation KLSubTest
- (double)test:(int)a s:(NSString *)s n:(NSNumber *)n {
    NSLog(@"%s", __func__);
    return n.doubleValue * 2;
}
@end

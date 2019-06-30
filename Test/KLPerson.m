//
//  KLPerson.m
//  Test
//
//  Created by karl on 2019/01/13.
//

#import "KLPerson.h"

@implementation KLPerson
- (void)personTest {
    NSLog(@"%s", __func__);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    NSLog(@"++++++++++");
}


@end

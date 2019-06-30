//
//  main.m
//  Test
//
//  Created by karl on 2019/01/06.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <map>
#include <string>
#import "KLSubTest.h"
#import "KLPerson.h"

using namespace std;

typedef void(*load_method_t)(id, SEL);

struct KLTest_struct {
    int a;
    int b;
    
    KLTest_struct(int _a, int _b): a(_a), b(_b) {
        
    }
    
    
};
void listTest();

int main(int argc, const char * argv[]) {
    
    KLPerson *p = [[KLPerson alloc] init];
    [p test:1 s:@"kl" n:@18.2];
    NSLog(@"---------------");
    
    return 0;
}


void listTest() {
    NSLog(@"%s",__func__);
    return;
    KLTest_struct *kt = nil;
    
    kt = (struct KLTest_struct *)
    realloc(kt,
            1 *
            sizeof(struct KLTest_struct));
    
    double d = 66.666;
    
    KLTest_struct k1(11, 21);
    KLTest_struct k2(12, 22);
    
    kt[0] = k1;
    kt[1] = k2;
    
    
    NSLog(@"%d--%d", kt[0].a, kt[0].b);
    NSLog(@"%d--%d", kt[1].a, kt[1].b);
    NSLog(@"%f", d);
}

void mapTest() {
    std::map<int, int> mapStudent;
//    mapStudent.insert(pair<int, int>(1, 10086));
    mapStudent[1] = 10086;
    
    std::map<int, int>::iterator i = mapStudent.find(1);
    if (i != mapStudent.end()) {
        
        NSLog(@"%d -- %d", i->second, i->first);
    } else {
        NSLog(@"not find");
    }
}

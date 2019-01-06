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
using namespace std;

union isa {
    isa() { }
    isa(uintptr_t value) : bits(value) { }
    
    Class cls;
    uintptr_t bits;
    struct {
        uintptr_t nonpointer        : 1;
        uintptr_t has_assoc         : 1;
        uintptr_t has_cxx_dtor      : 1;
        uintptr_t shiftcls          : 44; /*MACH_VM_MAX_ADDRESS 0x7fffffe00000*/
        uintptr_t magic             : 6;
        uintptr_t weakly_referenced : 1;
        uintptr_t deallocating      : 1;
        uintptr_t has_sidetable_rc  : 1;
        uintptr_t extra_rc          : 8;
    };
};


int main(int argc, const char * argv[]) {
    
    NSObject *o = [[NSObject alloc] init];
    objc_setAssociatedObject(o, "key", @"hahahah", OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_getAssociatedObject(o, "key");
    return 0;
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

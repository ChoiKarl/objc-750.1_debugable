/*
 * Copyright (c) 2004-2007 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
  Implementation of the weak / associative references for non-GC mode.
*/


#include "objc-private.h"
#include <objc/message.h>
#include <map>

#if _LIBCPP_VERSION
#   include <unordered_map>
#else
#   include <tr1/unordered_map>
    using namespace tr1;
#endif


// wrap all the murky C++ details in a namespace to get them out of the way.

namespace objc_references_support {
    struct DisguisedPointerEqual {
        bool operator()(uintptr_t p1, uintptr_t p2) const {
            return p1 == p2;
        }
    };
    
    struct DisguisedPointerHash {
        uintptr_t operator()(uintptr_t k) const {
            // borrowed from CFSet.c
#if __LP64__
            uintptr_t a = 0x4368726973746F70ULL;
            uintptr_t b = 0x686572204B616E65ULL;
#else
            uintptr_t a = 0x4B616E65UL;
            uintptr_t b = 0x4B616E65UL; 
#endif
            uintptr_t c = 1;
            a += k;
#if __LP64__
            a -= b; a -= c; a ^= (c >> 43);
            b -= c; b -= a; b ^= (a << 9);
            c -= a; c -= b; c ^= (b >> 8);
            a -= b; a -= c; a ^= (c >> 38);
            b -= c; b -= a; b ^= (a << 23);
            c -= a; c -= b; c ^= (b >> 5);
            a -= b; a -= c; a ^= (c >> 35);
            b -= c; b -= a; b ^= (a << 49);
            c -= a; c -= b; c ^= (b >> 11);
            a -= b; a -= c; a ^= (c >> 12);
            b -= c; b -= a; b ^= (a << 18);
            c -= a; c -= b; c ^= (b >> 22);
#else
            a -= b; a -= c; a ^= (c >> 13);
            b -= c; b -= a; b ^= (a << 8);
            c -= a; c -= b; c ^= (b >> 13);
            a -= b; a -= c; a ^= (c >> 12);
            b -= c; b -= a; b ^= (a << 16);
            c -= a; c -= b; c ^= (b >> 5);
            a -= b; a -= c; a ^= (c >> 3);
            b -= c; b -= a; b ^= (a << 10);
            c -= a; c -= b; c ^= (b >> 15);
#endif
            return c;
        }
    };
    
    struct ObjectPointerLess {
        bool operator()(const void *p1, const void *p2) const {
            return p1 < p2;
        }
    };
    
    struct ObjcPointerHash {
        uintptr_t operator()(void *p) const {
            return DisguisedPointerHash()(uintptr_t(p));
        }
    };

    // STL allocator that uses the runtime's internal allocator.
    
    template <typename T> struct ObjcAllocator {
        typedef T                 value_type;
        typedef value_type*       pointer;
        typedef const value_type *const_pointer;
        typedef value_type&       reference;
        typedef const value_type& const_reference;
        typedef size_t            size_type;
        typedef ptrdiff_t         difference_type;

        template <typename U> struct rebind { typedef ObjcAllocator<U> other; };

        template <typename U> ObjcAllocator(const ObjcAllocator<U>&) {}
        ObjcAllocator() {}
        ObjcAllocator(const ObjcAllocator&) {}
        ~ObjcAllocator() {}

        pointer address(reference x) const { return &x; }
        const_pointer address(const_reference x) const { 
            return x;
        }

        pointer allocate(size_type n, const_pointer = 0) {
            return static_cast<pointer>(::malloc(n * sizeof(T)));
        }

        void deallocate(pointer p, size_type) { ::free(p); }

        size_type max_size() const { 
            return static_cast<size_type>(-1) / sizeof(T);
        }

        void construct(pointer p, const value_type& x) { 
            new(p) value_type(x); 
        }

        void destroy(pointer p) { p->~value_type(); }

        void operator=(const ObjcAllocator&);

    };

    template<> struct ObjcAllocator<void> {
        typedef void        value_type;
        typedef void*       pointer;
        typedef const void *const_pointer;
        template <typename U> struct rebind { typedef ObjcAllocator<U> other; };
    };
  
    typedef uintptr_t disguised_ptr_t;
    inline disguised_ptr_t DISGUISE(id value) { return ~uintptr_t(value); }
    inline id UNDISGUISE(disguised_ptr_t dptr) { return id(~dptr); }
  
    class ObjcAssociation {
        uintptr_t _policy;
        id _value;
    public:
        ObjcAssociation(uintptr_t policy, id value) : _policy(policy), _value(value) {}
        ObjcAssociation() : _policy(0), _value(nil) {}

        uintptr_t policy() const { return _policy; }
        id value() const { return _value; }
        
        bool hasValue() { return _value != nil; }
    };

#if TARGET_OS_WIN32
    typedef hash_map<void *, ObjcAssociation> ObjectAssociationMap;
    typedef hash_map<disguised_ptr_t, ObjectAssociationMap *> AssociationsHashMap;
#else
    typedef ObjcAllocator<std::pair<void * const, ObjcAssociation> > ObjectAssociationMapAllocator;
    class ObjectAssociationMap : public std::map<void *, ObjcAssociation, ObjectPointerLess, ObjectAssociationMapAllocator> {
    public:
        void *operator new(size_t n) { return ::malloc(n); }
        void operator delete(void *ptr) { ::free(ptr); }
    };
    typedef ObjcAllocator<std::pair<const disguised_ptr_t, ObjectAssociationMap*> > AssociationsHashMapAllocator;
    class AssociationsHashMap : public unordered_map<disguised_ptr_t, ObjectAssociationMap *, DisguisedPointerHash, DisguisedPointerEqual, AssociationsHashMapAllocator> {
    public:
        void *operator new(size_t n) { return ::malloc(n); }
        void operator delete(void *ptr) { ::free(ptr); }
    };
#endif
}

using namespace objc_references_support;

// class AssociationsManager manages a lock / hash table singleton pair.
// Allocating an instance acquires the lock, and calling its assocations()
// method lazily allocates the hash table.

spinlock_t AssociationsManagerLock;

class AssociationsManager {
    // associative references: object pointer -> PtrPtrHashMap.
    static AssociationsHashMap *_map;
public:
    AssociationsManager()   { AssociationsManagerLock.lock(); }
    ~AssociationsManager()  { AssociationsManagerLock.unlock(); }
    
    AssociationsHashMap &associations() {
        if (_map == NULL)
            _map = new AssociationsHashMap();
        return *_map;
    }
};

AssociationsHashMap *AssociationsManager::_map = NULL;

// expanded policy bits.

enum { 
    OBJC_ASSOCIATION_SETTER_ASSIGN      = 0,
    OBJC_ASSOCIATION_SETTER_RETAIN      = 1,
    OBJC_ASSOCIATION_SETTER_COPY        = 3,            // NOTE:  both bits are set, so we can simply test 1 bit in releaseValue below.
    OBJC_ASSOCIATION_GETTER_READ        = (0 << 8), 
    OBJC_ASSOCIATION_GETTER_RETAIN      = (1 << 8), 
    OBJC_ASSOCIATION_GETTER_AUTORELEASE = (2 << 8)
}; 

id _object_get_associative_reference(id object, void *key) {
    // 默认初始化一个空value
    id value = nil;
    // 默认为ASSIGN策略
    uintptr_t policy = OBJC_ASSOCIATION_ASSIGN;
    {
        // 查找...
        AssociationsManager manager;
        AssociationsHashMap &associations(manager.associations());
        disguised_ptr_t disguised_object = DISGUISE(object);
        AssociationsHashMap::iterator i = associations.find(disguised_object);
        if (i != associations.end()) {
            ObjectAssociationMap *refs = i->second;
            ObjectAssociationMap::iterator j = refs->find(key);
            if (j != refs->end()) {
                // 找到就修改默认初始化的值和策略
                ObjcAssociation &entry = j->second;
                value = entry.value();
                policy = entry.policy();
                // 如果值是GETTER_RETAIN,就将当前value retain
                if (policy & OBJC_ASSOCIATION_GETTER_RETAIN) {
                    objc_retain(value);
                }
            }
        }
    }
    // 如果有值,并且策略为GETTER_AUTORELEASE,就将value autorelease
    if (value && (policy & OBJC_ASSOCIATION_GETTER_AUTORELEASE)) {
        objc_autorelease(value);
    }
    return value;
}

// 根据set策略,对value做处理
static id acquireValue(id value, uintptr_t policy) {
    switch (policy & 0xFF) {
    case OBJC_ASSOCIATION_SETTER_RETAIN:
        return objc_retain(value);
    case OBJC_ASSOCIATION_SETTER_COPY:
        return ((id(*)(id, SEL))objc_msgSend)(value, SEL_copy);
    }
    return value;
}

// SETTER_RETAIN 策略的可以release
static void releaseValue(id value, uintptr_t policy) {
    if (policy & OBJC_ASSOCIATION_SETTER_RETAIN) {
        return objc_release(value);
    }
}

struct ReleaseValue {
    // 通过关联属性对象,去release对象里的值
    void operator() (ObjcAssociation &association) {
        releaseValue(association.value(), association.policy());
    }
};

void _object_set_associative_reference(id object, void *key, id value, uintptr_t policy) {
    // retain the new value (if any) outside the lock.
    // 选默认初始化一个关联对象
    ObjcAssociation old_association(0, nil);
    id new_value = value ? acquireValue(value, policy) : nil;
    {
        AssociationsManager manager;
        // associations为懒加载的一个全局map,储存这所有类对应的关联属性映射表.
        // 每一个类都有一个自己的关联属性映射表,表里就存着key和key对应的关联属性.
        AssociationsHashMap &associations(manager.associations());
        // 类地址二进制取反
        disguised_ptr_t disguised_object = DISGUISE(object);
        if (new_value) {
            // break any existing association.
            // 从全局的map<key:ObjectAssociationMap>通过取反的二进制key里找到当前类关联属性映射表
            AssociationsHashMap::iterator i = associations.find(disguised_object);
            // 找到
            if (i != associations.end()) {
                // secondary table exists
                // 取出表
                ObjectAssociationMap *refs = i->second;
                // 从表里找传进来的key对应的关联对象
                ObjectAssociationMap::iterator j = refs->find(key);
                // 有关联对象,就将关联对象换成新传进来的.
                if (j != refs->end()) {
                    // 赋值给默认初始化的,方便最后将之前的关联对象release
                    old_association = j->second;
                    j->second = ObjcAssociation(policy, new_value);
                } else { // 没有关联对象就直接设置一个
                    (*refs)[key] = ObjcAssociation(policy, new_value);
                }
            } else { // 没有找到当前类的关联属性映射表
                // create the new association (first time).
                // 初始化一个关联属性映射表
                ObjectAssociationMap *refs = new ObjectAssociationMap;
                // 将关联属性映射表存入全局map里,key就是当前类的二进制取反
                associations[disguised_object] = refs;
                // 在将关联属性存入关联属性映射表
                (*refs)[key] = ObjcAssociation(policy, new_value);
                // 将当前类的isa.bits修改一下.
                object->setHasAssociatedObjects();
            }
        } else { // 如果传进来是一个空值
            // setting the association to nil breaks the association.
            // 查找过程如上,如果当前对象有对应的key值的关联对象,就移除掉.
            AssociationsHashMap::iterator i = associations.find(disguised_object);
            if (i !=  associations.end()) {
                ObjectAssociationMap *refs = i->second;
                ObjectAssociationMap::iterator j = refs->find(key);
                if (j != refs->end()) {
                    // 找到,赋值给默认初始化的,方便最后将之前的关联对象release
                    old_association = j->second;
                    refs->erase(j);
                }
            }
        }
    }
    // release the old value (outside of the lock).
    // release之前的的关联对象
    if (old_association.hasValue()) ReleaseValue()(old_association);
}

void _object_remove_assocations(id object) {
    vector< ObjcAssociation,ObjcAllocator<ObjcAssociation> > elements;
    {
        AssociationsManager manager;
        AssociationsHashMap &associations(manager.associations());
        if (associations.size() == 0) return;
        disguised_ptr_t disguised_object = DISGUISE(object);
        AssociationsHashMap::iterator i = associations.find(disguised_object);
        if (i != associations.end()) {
            // copy all of the associations that need to be removed.
            ObjectAssociationMap *refs = i->second;
            for (ObjectAssociationMap::iterator j = refs->begin(), end = refs->end(); j != end; ++j) {
                elements.push_back(j->second);
            }
            // remove the secondary table.
            delete refs;
            associations.erase(i);
        }
    }
    // the calls to releaseValue() happen outside of the lock.
    for_each(elements.begin(), elements.end(), ReleaseValue());
}

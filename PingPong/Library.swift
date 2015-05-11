//
//  Library.swift
//  PingPong
//
//  Created by Chris Eidhof on 26/04/15.
//  Copyright (c) 2015 objc.io. All rights reserved.
//

import Foundation

class Box<T> {
    let unbox: T
    init(_ value: T) { self.unbox = value }
}

enum Result<A> {
    case Failure(error: NSError?)
    case Success(value: Box<A>)
}

func downloadData(url: NSURL, callback: (Result<NSData>) -> ()) -> () {
    // TODO: this is not the right way
    let backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    dispatch_async(backgroundQueue) {
        var error: NSError? = nil
        if let data = NSData(contentsOfURL: url, options: nil, error: &error) {
            callback(Result.Success(value: Box(data)))
        } else {
            callback(Result.Failure(error: error))
        }
    }
    
}

func string(dict: [NSObject: AnyObject], key: String) -> String? {
    if let result: AnyObject = dict[key as NSObject] {
        return result as? String
    }
    return nil
}

func double(dict: [NSObject: AnyObject], key: String) -> Double? {
    let str : NSString? = string(dict,key)
    return str?.doubleValue
}

infix operator  <*> { associativity left precedence 150 }
func <*><A, B>(l: (A -> B)?, r: A?) -> B? {
    if let l1 = l {
        if let r1 = r {
            return l1(r1)
        }
        return nil
    }
    return nil
}

func pure<A>(x: A) -> A? {
    return x
}


func backgroundJob<A>(job: () -> A, completion: A -> ()) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), {
        let x = job()
        dispatch_async(dispatch_get_main_queue(), {
            completion(x)
        })
    })
}
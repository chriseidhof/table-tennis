//
//  QuadTree.swift
//  PingPong
//
//  Created by Chris Eidhof on 23/04/15.
//  Copyright (c) 2015 objc.io. All rights reserved.
//

import Foundation
import MapKit

let maxNumberOfPoints = 4

struct Point<A> {
    var point: CGPoint
    var value: Box<A>
}

struct QuadTree<A> {
    var node: QuadTreeNode<A>
    var region: CGRect
}

enum QuadTreeNode<A> {
    case Quadrants(nw: Box<QuadTree<A>>, ne: Box<QuadTree<A>>, se: Box<QuadTree<A>>,  sw: Box<QuadTree<A>>)
    case Points([Point<A>])
}

func empty<A>(region: CGRect) -> QuadTree<A> {
    return QuadTree(node: QuadTreeNode.Points([]), region: region)
}

func quadrants(rect: CGRect) -> (nw: CGRect, ne: CGRect, se: CGRect, sw: CGRect) {
    let size = CGSize(width: rect.size.width/2.0, height: rect.size.height/2.0)
    let arr = [
        CGPoint(x: rect.minX, y: rect.minY),
        CGPoint(x: rect.midX, y: rect.minY),
        CGPoint(x: rect.midX, y: rect.midY),
        CGPoint(x: rect.minX, y: rect.midY),
        ].map { CGRect(origin: $0, size: size) }
    return (arr[0], arr[1], arr[2], arr[3])
}

func map<A,B>(f: A -> B, x: Box<A>) -> Box<B> {
    return Box(f(x.unbox))
}

let mapRegion = CGRectMake(-90, -180, 180, 360)

func buildTree<A>(region: CGRect, elements: [Point<A>]) -> QuadTree<A> {
    return QuadTree(node: subdivide(region, elements), region: region)
}

func mapQuadrant<A>(condition: CGRect -> Bool, f: QuadTree<A> -> QuadTree<A>, var tree: QuadTree<A>) -> QuadTree<A> {
    switch tree.node {
    case let .Quadrants(nw, ne, se, sw):
        let (nwR, neR, seR, swR) = quadrants(tree.region)
        if condition(nwR) {
            tree.node = QuadTreeNode.Quadrants(nw: map(f,nw), ne: ne, se: se, sw: sw)
        } else if condition(neR) {
            tree.node = QuadTreeNode.Quadrants(nw: nw, ne: map(f,ne), se: se, sw: sw)
        } else if condition(seR) {
            tree.node = QuadTreeNode.Quadrants(nw: nw, ne: ne, se: map(f, se), sw: sw)
        } else if condition(swR) {
            tree.node = QuadTreeNode.Quadrants(nw: nw, ne: ne, se: se, sw: map(f, sw))
        }
        return tree
    default:
        return tree
    }
}

func insert<A>(element: Point<A>)(var tree: QuadTree<A>) -> QuadTree<A> {
    let (nwR, neR, seR, swR) = quadrants(tree.region)
    let point = element.point
    switch tree.node {
    case let .Quadrants(_, _, _, _):
        tree = mapQuadrant({ $0.contains(point) }, insert(element), tree)
    case .Points(var points):
        points.append(element)
        tree.node = subdivide(tree.region, points)
    }
    return tree
}

private func subdivide<A>(region: CGRect, points: [Point<A>]) -> QuadTreeNode<A> {
    if points.count <= maxNumberOfPoints {
        return QuadTreeNode.Points(points)
    } else {
        let (nwR, neR, seR, swR) = quadrants(region)
        let makeNode = { region in
            subdivide(region, filter(points) { region.contains($0.point) })
        }
        let makeTree = { region in Box(QuadTree(node: makeNode(region), region: region)) }
        return QuadTreeNode.Quadrants(nw: makeTree(nwR), ne: makeTree(neR), se: makeTree(seR), sw: makeTree(swR))
    }
}

func annotationsInRect<A>(region: CGRect, tree: QuadTree<A>) -> [Point<A>] {
    if tree.region.intersects(region) {
        switch tree.node {
        case let .Quadrants(ne, nw, se, sw):
            return flatMap([ne, nw, se, sw], { annotationsInRect(region, $0.unbox) })
        case .Points(let points):
            return points.filter { region.contains($0.point) }
        }
    } else {
        return []
    }
}

import simd

/*! Model object for something that is displayed on the screen. */
public class Node: PositionTweenable, ScaleTweenable, AngleTweenable {

  /* The position of the node relative to its parent. */
  public var position = float2(0, 0) {
    didSet { localTransformDirty = true }
  }

  /* The scale of the node (and its children). */
  public var scale = float2(1, 1) {
    didSet { localTransformDirty = true }
  }

  /* The rotation angle of the node in degrees, clockwise. */
  public var angle: Float = 0 {
    didSet { localTransformDirty = true }
  }

  /*! The thing that gets drawn for this node, if any. */
  public var visual: Visual? {
    willSet {
      visual?.node = nil
    }
    didSet {
      visual?.node = self
      visual?.needsRedraw = true
    }
  }

  /*! Convenience property so you don't have to cast visual all the time. */
  public var sprite: Sprite {
    if let sprite = visual as? Sprite {
      return sprite
    } else {
      fatalError("Visual for node '\(name)' is not a sprite")
    }
  }

  /*! Convenience property so you don't have to cast visual all the time. */
  public var shape: Shape {
    if let shape = visual as? Shape {
      return shape
    } else {
      fatalError("Visual for node '\(name)' is not a shape")
    }
  }

  /*! The parent node, if any. */
  private(set) public weak var parent: Node?

  /*! The child nodes, if any. */
  private(set) public var children: [Node] = []

  /*! For debugging and finding nodes by name. */
  public var name = ""

  /*! For identifying nodes by a numeric value. */
  public var tag = 0

  /*! Any arbitrary object that you want to associate with this node. */
  public var userData: AnyObject?

  public init() { }

  deinit {
    //print("deinit \(self)")
  }

  /*! The transform for this node. The transform of the parent has already been
      applied to this, so it's in world coordinates. */
  private(set) public var transform = float4x4.identity

  /*! The transform in object coordinates. */
  private var localTransform = float4x4.identity
  private var localTransformDirty = true

  // MARK: - Building the scene graph

  public func add(child: Node) {
    insert(child, atIndex: children.count)
  }

  public func insert(child: Node, atIndex index: Int) {
    assert(child.parent == nil, "Child node already has parent")
    assert(children.find(child) == nil, "Node already contains child")

    children.insert(child, atIndex: index)
    child.parent = self
  }

  public func remove(child: Node) {
    if let index = children.find(child) {
      children.removeAtIndex(index)
      child.parent = nil
    }
  }

  public func remove(children list: [Node]) {
    for child in list {
      remove(child)
    }
  }

  public func removeAllChildren() {
    for child in children {
      child.parent = nil
    }
    children.removeAll()
  }

  public func removeFromParent() {
    parent?.remove(self)
  }

  // MARK: - Inspecting the scene graph

  public func childNode(withName name: String) -> Node? {
    for child in children {
      if child.name == name { return child }
    }
    return nil
  }

  public func childNode(withTag tag: Int) -> Node? {
    for child in children {
      if child.tag == tag { return child }
    }
    return nil
  }

  public func inParentHierarchy(other: Node) -> Bool {
    var p = parent
    while p != nil {
      if p === other { return true }
      p = p?.parent
    }
    return false
  }

  // MARK: - Transforms

  private func calculateLocalTransform() {
    var c: Float = 1
    var s: Float = 0

    if angle != 0 {
      let radians = angle.degreesToRadians
      s = sinf(radians)
      c = cosf(radians)
    }

    localTransform = float4x4([
      [  c * scale.x, s * scale.x, 0, 0, ],
      [ -s * scale.y, c * scale.y, 0, 0, ],
      [            0,           0, 1, 0, ],
      [   position.x,  position.y, 0, 1  ]])
  }

  private func updateTransform() {
    if localTransformDirty {
      calculateLocalTransform()
      localTransformDirty = false
    }

    if let parent = parent {
      transform = parent.transform * localTransform
    } else {
      transform = localTransform
    }
  }

  /*! Used internally to walk the scene graph. Updates the transform for the 
      node if necessary, and then visits its children. */
  public func visit(parentIsDirty: Bool) {
    let dirty = parentIsDirty || localTransformDirty
    if dirty {
      updateTransform()
      visual?.needsRedraw = true
    }

    for child in children {
      child.visit(dirty)
    }

    debug.nodeCount += 1
  }
}

extension Node: CustomStringConvertible {
  public var description: String {
    return "node '\(name)'"
  }
}

extension Node {
  /*!
    Orients the node in the direction that it is moving by tweening its rotation
    angle. This assumes that at 0 degrees the node is facing up.

    Parameters:

    - rate How fast the node rotates. Must have a value between 0.0 and 1.0,
           where smaller means slower; 1.0 is instantaneous.
   */
  public func rotateToVelocity(velocity: float2, rate: Float) {
    // Determine what the rotation angle of the node ought to be based on the
    // current velocity of its physics body. This assumes that at 0 degrees the
    // node is pointed up, not to the right, so to compensate we add 90 degrees
    // from the calculated angle.
    let newAngle = (atan2(velocity.y, velocity.x)).radiansToDegrees + 90

    // This always makes the node rotate over the shortest possible distance.
    // Because the range of atan2() is -180 to 180 degrees, a rotation from,
    // -170 to -190 would otherwise be from -170 to 170, which makes the node
    // rotate the wrong way (and the long way) around. We adjust the angle to
    // go from 190 to 170 instead, which is equivalent to -170 to -190.
    if newAngle - angle > 180 {
      angle += 360
    } else if angle - newAngle > 180 {
      angle -= 360
    }

    // Use the "standard exponential slide" to slowly tween to the new angle.
    // The greater the value of rate, the faster this goes.
    angle += (newAngle - angle) * rate
  }
}

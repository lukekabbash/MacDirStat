import Foundation

extension ScanSession {
    /// Verifies the arena and linked child lists before persisted data reaches
    /// navigation, charting, or projection code that assumes a valid tree.
    var hasValidTreeStructure: Bool {
        ScanSessionTreeValidator(nodes: nodes).validate()
    }
}

private struct ScanSessionTreeValidator {
    let nodes: [FileNode]

    func validate() -> Bool {
        guard hasValidNodeHeaders() else { return false }
        guard let claimedChildren = validateChildLists() else { return false }
        guard claimedChildren.dropFirst().allSatisfy({ $0 }) else { return false }
        return reachableNodeCount() == nodes.count
    }

    private func hasValidNodeHeaders() -> Bool {
        guard !nodes.isEmpty, UInt64(nodes.count) <= UInt64(UInt32.max) else { return false }
        guard nodes[0].kind == .root,
              nodes[0].parentID == .invalid,
              nodes[0].nextSiblingID == .invalid
        else { return false }

        for index in nodes.indices {
            let node = nodes[index]
            let canContainChildren = node.kind == .root || node.kind == .directory
            guard canContainChildren || (node.childCount == 0 && node.firstChildID == .invalid) else {
                return false
            }
            guard isValidOptionalNodeID(node.firstChildID),
                  isValidOptionalNodeID(node.nextSiblingID)
            else { return false }

            if index == 0 { continue }
            guard node.kind != .root,
                  let parentIndex = validIndex(for: node.parentID),
                  parentIndex != index
            else { return false }
        }
        return true
    }

    private func validateChildLists() -> [Bool]? {
        var claimed = Array(repeating: false, count: nodes.count)

        for parentIndex in nodes.indices {
            let parent = nodes[parentIndex]
            var current = parent.firstChildID
            var actualChildCount = 0

            while current != .invalid {
                guard let childIndex = validIndex(for: current),
                      childIndex != 0,
                      !claimed[childIndex],
                      nodes[childIndex].parentID.rawValue == UInt32(parentIndex)
                else { return nil }

                claimed[childIndex] = true
                actualChildCount += 1
                guard actualChildCount <= nodes.count else { return nil }
                current = nodes[childIndex].nextSiblingID
            }

            guard actualChildCount == Int(parent.childCount) else { return nil }
        }
        return claimed
    }

    private func reachableNodeCount() -> Int {
        var queue = [0]
        queue.reserveCapacity(nodes.count)
        var cursor = 0

        while cursor < queue.count {
            let parentIndex = queue[cursor]
            cursor += 1
            var childID = nodes[parentIndex].firstChildID
            while childID != .invalid {
                guard let childIndex = validIndex(for: childID) else { return 0 }
                queue.append(childIndex)
                childID = nodes[childIndex].nextSiblingID
            }
        }
        return queue.count
    }

    private func isValidOptionalNodeID(_ id: NodeID) -> Bool {
        id == .invalid || validIndex(for: id) != nil
    }

    private func validIndex(for id: NodeID) -> Int? {
        guard id != .invalid, let index = Int(exactly: id.rawValue), nodes.indices.contains(index) else {
            return nil
        }
        return index
    }
}

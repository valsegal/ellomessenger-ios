import SwiftSignalKit
import Postbox

public extension ElloAppEngine.EngineData.Item {
    enum OrderedLists {
        public struct ListItems: ElloAppEngineDataItem, PostboxViewDataItem {
            public typealias Result = [OrderedItemListEntry]

            private let collectionId: Int32

            public init(collectionId: Int32) {
                self.collectionId = collectionId
            }

            var key: PostboxViewKey {
                return .orderedItemList(id: self.collectionId)
            }

            func extract(view: PostboxView) -> Result {
                guard let view = view as? OrderedItemListView else {
                    preconditionFailure()
                }
                return view.items
            }
        }
    }
}

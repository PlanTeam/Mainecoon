import XCTest
@testable import Mainecoon

class MainecoonTests: XCTestCase {
    var groupType: ModelType! = nil
    var userType: ModelType! = nil
    
    lazy var initialized: Bool = {
        do {
            let db = try Server(hostname: "localhost")["mainecoontest"]
            
            self.groupType = registerModel(named: ("group", "groups"), withSchematics: [
                "name": (.string, true)
                ], inDatabase: db)
            
            self.userType = registerModel(named: ("user", "users"), withSchematics: [
                "username": (.nonEmptyString, true),
                "age": (.number, false),
                "group": (.reference(model: self.groupType), true)
                ], inDatabase: db)
            
            return true
        } catch {
            return false
        }
    }()
    
    override func setUp() {
        if !initialized {
            print(initialized)
        }
    }
    
    func testExample() throws {
        XCTAssertNil(try? self.groupType.makeEntity(fromDocument: ["bob": true]))
        
        let realGroup = try self.groupType.makeEntity(fromDocument: ["name": "bob"])
        
        XCTAssertNil(try? self.userType.makeEntity(fromDocument: ["username": "Bert", "age": false, "group": ~ObjectId()]))
        XCTAssertNil(try? self.userType.makeEntity(fromDocument: ["username": "Bert", "age": false, "group": realGroup["_id"]]))
        XCTAssertNil(try? self.userType.makeEntity(fromDocument: ["username": "Bert", "group": ~ObjectId()]))
        
        let realUser = try self.userType.makeEntity(fromDocument: ["username": "Bert", "group": realGroup["_id"], "age": 123])
        
        guard let group = realUser[reference: "group"] else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(group["name"], "bob")
    }
    
    static var allTests : [(String, (MainecoonTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}

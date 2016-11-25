import XCTest
@testable import Mainecoon

class MainecoonTests: XCTestCase {
    func testEmbeddedDocuments() throws {
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group

        try realGroup.store()
        try db.server.fsync(async: false, blocking: true)

        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.makeReference(), "age": 123]) as User
        
        try realUser.setEmbeddedInstance(toReferenceOf: realGroup, withProjection: ["name"], forKey: "embeddedgroup")
        
        try realGroup.store()
        try realUser.store()
        
        guard let reference = realUser.getEmbeddedInstance(forKey: "embeddedgroup") else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(reference.embeddedDocument["name"] as? String, "bob")
        
        guard let groupReference = try reference.resolveReference() as? Group else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(groupReference.name, "bob")
    }
    
    func testEntityProjections() throws {
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        try realGroup.store()
        try db.server.fsync(async: false, blocking: true)
        
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.makeReference(), "age": 123]) as User
        
        try realUser.store()
        try db.server.fsync(async: false, blocking: true)
        
        let user = try User(fromIdentifier: realUser.identifier, projectedBy: ["username", "group"])
        
        XCTAssertNil(user.getProperty(forKey: "age") as String?)
        XCTAssertEqual(user.username, "Bert")
        
        user.setProperty(toValue: "Henk", forKey: "username")
        try user.store()
        try db.server.fsync(async: false, blocking: true)

        let user2 = try User(fromIdentifier: realUser.identifier)
        
        XCTAssertEqual(user2.username, "Henk")
        XCTAssertEqual(user2.getProperty(forKey: "age") as Int?, 123)
    }
    
    override func setUp() {
        _ = groupModel
        _ = userModel
        _ = reflectedUserModel
    }
    
    func testEntityRelations() throws {
        XCTAssertNil(try? Group.make(fromDocument: ["bob": true]) as Group)
        
        let realGroup = try Group.make(fromDocument: ["name": "bob"]) as Group
        
        try realGroup.store()
        try db.server.fsync(async: false, blocking: true)
        
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "age": false, "group": ObjectId()]) as User)
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "age": false, "group": realGroup.identifier]) as User)
        XCTAssertNil(try? User.make(fromDocument: ["username": "Bert", "group": ObjectId()]) as User)
        
        let realUser = try User.make(fromDocument: ["username": "Bert", "group": realGroup.identifier, "age": 123]) as User
        
        guard let group = realUser.group else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(group.name, "bob")
    }
    
    func testReflection() throws {
        let user = try ReflectedUser.make(fromDocument: [
                "username": "henk",
                "password": "bob",
                "age": 20,
                "awesome": true
            ]) as ReflectedUser
        
        XCTAssertEqual(user.username, "henk")
        XCTAssertEqual(user.password, "bob")
        XCTAssertEqual(user.age, 20)
        XCTAssertEqual(user.awesome, true)
        
        try user.store()
        try db.server.fsync(async: false, blocking: true)
        
        let user2 = try ReflectedUser(fromIdentifier: user.identifier)
        
        XCTAssertEqual(user2.username, "henk")
        XCTAssertEqual(user2.password, "bob")
        XCTAssertEqual(user2.age, 20)
        XCTAssertEqual(user2.awesome, true)
    }
    
    static var allTests : [(String, (MainecoonTests) -> () throws -> Void)] {
        return [
            ("testEntityRelations", testEntityRelations),
            ("testEntityProjections", testEntityProjections),
        ]
    }
}

let db = try! Server(hostname: "localhost")["mainecoontest"]

let groupModel = try! registerModel(named: ("group", "groups"), withSchematics: [
    "name": (.string, true)
    ], inDatabase: db, instanceType: Group.self)

let userModel = try! registerModel(named: ("user", "users"), withSchematics: [
    "username": (.nonEmptyString, true),
    "age": (.number, false),
    "group": (.reference(model: Group.self), true)
    ], inDatabase: db, instanceType: User.self)

let reflectedUserModel = try! registerModel(named: ("reflecteduser", "reflectedusers"), withSchematics: [
    "username": (.nonEmptyString, true),
    "password": (.nonEmptyString, true),
    "age": (.number, true),
    "awesome": (.bool, true)
    ], inDatabase: db, instanceType: ReflectedUser.self)


class ReflectedUser: ReflectedDocumentInstance {
    /// The identifier of this Instance. Usually but not necessarily an ObjectId
    public var identifier: ValueConvertible
    var model: Model!
    
    var username: String = ""
    var password: String = ""
    var age: Int = -1
    var awesome: Bool = false
    
    required init() {
        self.identifier = ObjectId()
    }
}

class Group: BasicInstance {
    var name: String {
        get {
            return self.getProperty(forKey: "name") ?? ""
        }
        set {
            self.setProperty(toValue: newValue, forKey: "name")
        }
    }
}

class User: BasicInstance {
    var username: String {
        get {
            return self.getProperty(forKey: "username") ?? ""
        }
        set {
            self.setProperty(toValue: newValue, forKey: "username")
        }
    }
    
    var group: Group? {
        get {
            do {
                return try self.getReference(forKey: "group") as? Group
            } catch {
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                return
            }
            
            self.setReference(toReferenceOf: newValue, forKey: "group")
        }
    }
}

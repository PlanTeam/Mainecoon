import Foundation
import BSON

public struct Schema: ValueConvertible, ExpressibleByDictionaryLiteral {
    public func makeBSONPrimitive() -> BSONPrimitive {
        return [
            "$and": Document(array: fields).makeBSONPrimitive()
        ] as Document
    }
    
    let fields: [SchemaMetadata]
    var requirements: [(name: String, requirement: SchemaMetadata.FieldRequirement)] {
        return fields.map { field in
            switch field {
            case .optional(let name, let requirement): return (name, requirement)
            case .required(let name, let requirement): return (name, requirement)
            }
        }
    }
    
    public init(dictionaryLiteral elements: (String, (match: SchemaMetadata.FieldRequirement, required: Bool))...) {
        self.fields = elements.map { name, requirement in
            if requirement.required {
                return SchemaMetadata.required(named: name, matching: requirement.match)
            } else {
                return SchemaMetadata.optional(named: name, matching: requirement.match)
            }
        }
    }
    
    public func validate(_ document: Document, ignoringFields ignoredFields: Projection? = nil, allowExtraKeys: Bool = true) -> ValidationResult {
        fieldLoop: for field in fields {
            if let ignoredFields = ignoredFields, ignoredFields.makeDocument().keys.contains(field.name) {
                continue fieldLoop
            }
            
            let result = field.validate(against: document)
            
            guard case .valid = result else {
                return result
            }
        }
        
        return .valid
    }
    
    public func validate(_ document: Document, validatingFields validatedFields: Projection, allowExtraKeys: Bool = true) -> ValidationResult {
        fieldLoop: for field in fields {
            guard validatedFields.makeDocument().keys.contains(field.name) else {
                continue fieldLoop
            }
            
            let result = field.validate(against: document)
            
            guard case .valid = result else {
                return result
            }
        }
        
        return .valid
    }
    
    public enum ValidationResult: Error {
        case valid
        case invalid(reason: String)
    }
    
    public enum SchemaMetadata: ValueConvertible {
        public indirect enum FieldRequirement: ValueConvertible {
            case string, number, date, anyObject, bool, nonEmptyString, objectId
            case reference(model: Instance.Type)
            case object(matching: Schema)
            case enumeration([ValueConvertible])
            case array(of: FieldRequirement)
            case any(requirement: [FieldRequirement])
            case exactly(ValueConvertible)
            case all(requirements: [FieldRequirement])
            case matchingRegex(RegularExpression)
            case anything
            
            public func validate(against value: ValueConvertible?, forKey key: String, allowExtraKeys: Bool = true) -> ValidationResult {
                guard let value = value else {
                    return .invalid(reason: "Value is empty and therefore doesn't match")
                }
                
                switch (self, value) {
                case (.string, is String):
                    return .valid
                case (.number, is Double):
                    return .valid
                case (.number, is Int32):
                    return .valid
                case (.number, is Int64):
                    return .valid
                case (.anyObject, is Document):
                    return .valid
                case (.bool, is Bool):
                    return .valid
                case (.objectId, is ObjectId):
                    return .valid
                case (.nonEmptyString, is String):
                    return (value.string?.characters.count) ?? 0 > 0 ? .valid : .invalid(reason: "\(key) is of type String but is empty")
                case (.reference(let type), _):
                    do {
                        if let referenceDocument = value as? Document {
                            guard let model = try? type.makeModel() else {
                                return .invalid(reason: "\(key) is a reference to an Instance of \(type). But the Instance does not have a registered Model")
                            }
                            
                            guard let reference = DBRef(referenceDocument, inDatabase: model.collection.database) else {
                                return .invalid(reason: "\(key) is a reference to an Instance of \(type). But the Document found at this key does not resolve to a usable DBRef.")
                            }
                            
                            let notFoundReason = "\(key) is a reference to an Instance of \(type). But it can't be resolved to a Document."
                            
                            do {
                                guard try reference.resolve() != nil else {
                                    return .invalid(reason: notFoundReason)
                                }
                                
                                return .valid
                            } catch {
                                return .invalid(reason: notFoundReason)
                            }
                        } else {
                            return try type.count(matching: "_id" == value) == 1 ? .valid : .invalid(reason: "\(key) is a reference to an Instance of \(type). But a matching model in this collection could not be found")
                        }
                    } catch {
                        return .invalid(reason: "Database lookup error")
                    }
                case (.object(let schema), is Document):
                    for match in schema.fields {
                        let result = match.validate(against: value, inScope: key)
                        
                        guard case .valid = result else {
                            return result
                        }
                    }
                    return .valid
                case (.enumeration(let array), _):
                    for arrayValue in array where value.makeBSONPrimitive().makeBSONBinary() == arrayValue.makeBSONPrimitive().makeBSONBinary() && value.makeBSONPrimitive().typeIdentifier == arrayValue.makeBSONPrimitive().typeIdentifier {
                        return .valid
                    }
                    
                    return .invalid(reason: "\(key) does not match value in enumeration \(array)")
                case (.array(let elementRequirement), is Document):
                    let array = value.documentValue ?? []
                    
                    guard array.validatesAsArray() else {
                        return .invalid(reason: "\(key) is not an array")
                    }
                    
                    for element in array.arrayValue {
                        let result = elementRequirement.validate(against: element, forKey: key)
                        
                        guard case .valid = result else {
                            return result
                        }
                    }
                    
                    return .valid
                case (.any(let requirements), _):
                    for requirement in requirements {
                        if case .valid = requirement.validate(against: value, forKey: key) {
                            return .valid
                        }
                    }
                    
                    return .invalid(reason: "\(key) does not match any provided requirement")
                case (.exactly(let val), _):
                    return value.makeBSONPrimitive().makeBSONBinary() == val.makeBSONPrimitive().makeBSONBinary() && value.makeBSONPrimitive().typeIdentifier == val.makeBSONPrimitive().typeIdentifier ? .valid : .invalid(reason: "\(key) does not match \(val)")
                case (.all(let requirements), _):
                    for requirement in requirements {
                        let requirement = requirement.validate(against: value, forKey: key)
                        
                        guard case .valid = requirement else {
                            return requirement
                        }
                    }
                    
                    return .valid
                case (.anything, _):
                    return .valid
                case (.matchingRegex(let regex), is String):
                    return value.string?.range(of: regex.pattern, options: .regularExpression) != nil ? .valid : .invalid(reason: "\(key) does not match provided regularexpression")
                default:
                    return .invalid(reason: "\(key) does not match expeced type \(self.stringValue)")
                }
            }
            
            var stringValue: String {
                return "test"
            }
            
            public func makeBSONPrimitive() -> BSONPrimitive {
                switch self {
                case .string:
                    return ["$type": "string"] as Document
                case .number:
                    return ["$or": [
                        ["$type": "double"] as Document,
                        ["$type": "int"] as Document,
                        ["$type": "long"] as Document
                        ] as Document] as Document
                case .date:
                    return ["$type": "date"] as Document
                case .anyObject:
                    return ["$type": "object"] as Document
                case .bool:
                    return ["$type": "bool"] as Document
                case .nonEmptyString:
                    return ["$and": [
                        ["$type": "string"] as Document,
                        ["$ne": ""] as Document
                        ] as Document] as Document
                case .reference(_), .objectId:
                    return ["$type": "objectId"] as Document
                case .enumeration(let values):
                    return ["$in": Document(array: values)] as Document
                case .array(let requirement):
                    return ["$not": ["$elemMatch": ["$not": requirement] as Document] as Document] as Document
                case .any(let requirements):
                    return ["$or":
                        BSON.Document(array: requirements)
                    ] as Document
                case .exactly(let val):
                    return val.makeBSONPrimitive()
                case .all(let requirements):
                    return ["$and":
                        Document(array: requirements)
                    ] as Document
                case .matchingRegex(let regex):
                    return regex
                case .anything:
                    return [:] as Document
                case .object(let schema):
                    return schema.makeBSONPrimitive()
                }
            }
        }
        
        case optional(named: String, matching: FieldRequirement)
        case required(named: String, matching: FieldRequirement)
        
        var name: String {
            switch self {
            case .optional(let name, _): return name
            case .required(let name, _): return name
            }
        }
        
        public func validate(against value: ValueConvertible?, inScope scope: String? = nil, allowExtraKeys: Bool = true) -> ValidationResult {
            let scope = scope ?? ""
            
            switch self {
            case .optional(let name, let requirement):
                guard let value = value?.documentValue?[raw: name] else {
                    return .valid
                }
                
                return requirement.validate(against: value, forKey: scope + name)
            case .required(let name, let requirement):
                return requirement.validate(against: value?.documentValue?[raw: name], forKey: scope + name)
            }
        }
        
        public func makeBSONPrimitive() -> BSONPrimitive {
            switch self {
            case .optional(let name, let requirement):
                // TODO: FIX
                return ["$or": [
                            [name: requirement] as Document,
                        [name:
                            ["$exists": false] as Document
                        ] as Document
                    ] as Document] as Document
            case .required(let name, let requirement):
                return [name: requirement] as Document
            }
        }
    }
}

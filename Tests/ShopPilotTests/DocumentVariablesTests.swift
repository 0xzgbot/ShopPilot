import XCTest
@testable import ShopPilotCore

/// Unit tests for DocumentVariablesModel — add, update, delete, filter, and persistence.
final class DocumentVariablesModelTests: XCTestCase {
    
    private var model: DocumentVariablesModel!
    private var testDir: URL!
    
    override func setUp() {
        super.setUp()
        
        // Use a temporary directory for persistence to avoid polluting real storage.
        testDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DocumentVariablesModelTests_\(UUID().uuidString)"
        )
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        
        let mockFM = FileManager.default
        model = DocumentVariablesModel(fileManager: mockFM, storageKey: "test_vars")
    }
    
    override func tearDown() {
        super.tearDown()
        model = nil
        try? FileManager.default.removeItem(at: testDir)
    }
    
    // MARK: - Add Variable Tests
    
    func testAddVariableCreatesNewEntry() {
        let variable = model.addVariable(key: "Material", value: "Aluminum 6061", category: "Material")
        
        XCTAssertEqual(model.variables.count, 1)
        XCTAssertEqual(variable.key, "Material")
        XCTAssertEqual(variable.value, "Aluminum 6061")
        XCTAssertEqual(variable.category, "Material")
        XCTAssertNotNil(variable.id)
    }
    
    func testAddVariableDefaultsCategory() {
        let variable = model.addVariable(key: "Project", value: "Test")
        
        XCTAssertEqual(variable.category, DocumentVariable.defaultCategory)
        XCTAssertEqual(model.variables[0].category, "General")
    }
    
    func testAddMultipleVariables() {
        _ = model.addVariable(key: "Material", value: "Steel", category: "Material")
        _ = model.addVariable(key: "Stock", value: "12x12x1", category: "Stock")
        _ = model.addVariable(key: "Project", value: "Sign", category: "Project")
        
        XCTAssertEqual(model.variables.count, 3)
    }
    
    // MARK: - Update Variable Tests
    
    func testUpdateVariableChangesKeyAndValue() {
        let variable = model.addVariable(key: "OldKey", value: "OldValue", category: "Cat")
        let originalId = variable.id
        
        let updated = model.updateVariable(id: originalId, key: "NewKey", value: "NewValue")
        
        XCTAssertTrue(updated)
        XCTAssertEqual(model.variables[0].key, "NewKey")
        XCTAssertEqual(model.variables[0].value, "NewValue")
        XCTAssertEqual(model.variables[0].id, originalId) // ID preserved
    }
    
    func testUpdateVariablePreservesCategory() {
        let variable = model.addVariable(key: "Key", value: "Val", category: "Special")
        
        _ = model.updateVariable(id: variable.id, key: "Key2", value: "Val2")
        
        XCTAssertEqual(model.variables[0].category, "Special")
    }
    
    func testUpdateNonexistentVariableReturnsFalse() {
        let fakeId = UUID()
        let updated = model.updateVariable(id: fakeId, key: "NewKey", value: "NewValue")
        
        XCTAssertFalse(updated)
        XCTAssertTrue(model.variables.isEmpty)
    }
    
    // MARK: - Delete Variable Tests
    
    func testDeleteVariableRemovesEntry() {
        let v1 = model.addVariable(key: "A", value: "1")
        let v2 = model.addVariable(key: "B", value: "2")
        
        let deleted = model.deleteVariable(id: v1.id)
        
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.variables.count, 1)
        XCTAssertEqual(model.variables[0].key, "B")
    }
    
    func testDeleteNonexistentVariableReturnsFalse() {
        let fakeId = UUID()
        let deleted = model.deleteVariable(id: fakeId)
        
        XCTAssertFalse(deleted)
        XCTAssertTrue(model.variables.isEmpty)
    }
    
    func testDeleteLastVariable() {
        let v = model.addVariable(key: "Only", value: "One")
        
        _ = model.deleteVariable(id: v.id)
        
        XCTAssertTrue(model.variables.isEmpty)
    }
    
    // MARK: - Filter by Category Tests
    
    func testVariablesByCategoryFiltersCorrectly() {
        _ = model.addVariable(key: "A", value: "1", category: "Mat")
        _ = model.addVariable(key: "B", value: "2", category: "Stock")
        _ = model.addVariable(key: "C", value: "3", category: "Mat")
        
        let matVars = model.variables(byCategory: "Mat")
        XCTAssertEqual(matVars.count, 2)
        XCTAssertTrue(matVars.allSatisfy { $0.category == "Mat" })
    }
    
    func testVariablesByCategoryEmptyReturnsAll() {
        _ = model.addVariable(key: "A", value: "1", category: "Cat1")
        _ = model.addVariable(key: "B", value: "2", category: "Cat2")
        
        let allVars = model.variables(byCategory: "")
        XCTAssertEqual(allVars.count, 2)
    }
    
    func testVariablesByCategoryNoMatchReturnsEmpty() {
        _ = model.addVariable(key: "A", value: "1", category: "Mat")
        
        let none = model.variables(byCategory: "Nonexistent")
        XCTAssertTrue(none.isEmpty)
    }
    
    // MARK: - Categories Computed Property
    
    func testCategoriesReturnsSortedUnique() {
        _ = model.addVariable(key: "A", value: "1", category: "Zebra")
        _ = model.addVariable(key: "B", value: "2", category: "Alpha")
        _ = model.addVariable(key: "C", value: "3", category: "Zebra")
        
        let cats = model.categories
        XCTAssertEqual(cats, ["Alpha", "Zebra"])
    }
    
    func testCategoriesEmptyWhenNoVariables() {
        XCTAssertTrue(model.categories.isEmpty)
    }
    
    // MARK: - Persistence Tests
    
    func testSaveAndLoadRoundTrip() async {
        _ = model.addVariable(key: "Material", value: "Pine", category: "Material")
        _ = model.addVariable(key: "Stock", value: "6x6x1", category: "Stock")
        
        let saved = await model.save()
        XCTAssertTrue(saved)
        
        // Create a fresh model and load
        let freshModel = DocumentVariablesModel(fileManager: FileManager.default, storageKey: "test_vars")
        // Load from the same directory
        let loadedModel = DocumentVariablesModel(fileManager: FileManager.default, storageKey: "test_vars")
        
        let loaded = await loadedModel.load()
        XCTAssertTrue(loaded)
        XCTAssertEqual(loadedModel.variables.count, 2)
        XCTAssertEqual(loadedModel.variables[0].key, "Material")
        XCTAssertEqual(loadedModel.variables[0].value, "Pine")
    }
    
    func testLoadNonexistentFileReturnsFalse() async {
        let freshModel = DocumentVariablesModel(fileManager: FileManager.default, storageKey: "nonexistent_key_xyz")
        let loaded = await freshModel.load()
        
        XCTAssertFalse(loaded)
        XCTAssertTrue(freshModel.variables.isEmpty)
    }
    
    func testClearRemovesAllVariables() async {
        _ = model.addVariable(key: "A", value: "1")
        _ = model.addVariable(key: "B", value: "2")
        
        await model.save()
        XCTAssertEqual(model.variables.count, 2)
        
        await model.clear()
        
        XCTAssertTrue(model.variables.isEmpty)
    }
    
    // MARK: - DocumentVariable Identifiable/Hashable Tests
    
    func testDocumentVariableHasUUID() {
        let var1 = DocumentVariable(key: "Key", value: "Val")
        XCTAssertNotNil(var1.id)
    }
    
    func testDocumentVariableEquality() {
        let var1 = DocumentVariable(key: "Key", value: "Val", category: "Cat")
        let var2 = DocumentVariable(key: "Key", value: "Val", category: "Cat")
        
        // Different UUIDs, so not equal (Identifiable uses id)
        XCTAssertNotEqual(var1, var2)
    }
    
    func testDocumentVariableSameIdEqual() {
        let id = UUID()
        let var1 = DocumentVariable(id: id, key: "Key", value: "Val")
        let var2 = DocumentVariable(id: id, key: "Key", value: "Val")
        
        XCTAssertEqual(var1, var2)
    }
    
    func testDocumentVariableHashable() {
        let var1 = DocumentVariable(key: "Key", value: "Val")
        let var2 = DocumentVariable(key: "Key", value: "Val")
        
        let hashSet: Set<DocumentVariable> = [var1, var2]
        // Two different UUIDs → two distinct entries
        XCTAssertEqual(hashSet.count, 2)
    }
}

import Foundation
import OpenAI
import Testing

struct ToolDefinitionTests {
    // MARK: - Bash tool

    @Test func bashToolHasCorrectName() {
        let tool = OpenAIAssistantService.bashToolParam
        #expect(tool.function.name == "bash")
    }

    @Test func bashToolHasDescription() throws {
        let tool = OpenAIAssistantService.bashToolParam
        #expect(tool.function.description != nil)
        #expect(try !#require(tool.function.description?.isEmpty))
    }

    @Test func bashToolRequiresCommandParameter() throws {
        let tool = OpenAIAssistantService.bashToolParam
        let params = try #require(tool.function.parameters)
        let schema = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: schema) as? [String: Any]
        let required = try #require(json?["required"] as? [String])
        #expect(required.contains("command"))
    }

    @Test func bashToolDefinesWorkingDirectoryParameter() throws {
        let tool = OpenAIAssistantService.bashToolParam
        let params = try #require(tool.function.parameters)
        let schema = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: schema) as? [String: Any]
        let properties = try #require(json?["properties"] as? [String: Any])
        #expect(properties.keys.contains("command"))
        #expect(properties.keys.contains("working_directory"))
    }

    @Test func bashToolHasStrictModeEnabled() {
        let tool = OpenAIAssistantService.bashToolParam
        #expect(tool.function.strict == true)
    }

    // MARK: - Datetime tool

    @Test func datetimeToolHasCorrectName() {
        let tool = OpenAIAssistantService.datetimeToolParam
        #expect(tool.function.name == "datetime")
    }

    @Test func datetimeToolHasDescription() throws {
        let tool = OpenAIAssistantService.datetimeToolParam
        #expect(tool.function.description != nil)
        #expect(try !#require(tool.function.description?.isEmpty))
    }

    @Test func datetimeToolHasStrictModeEnabled() {
        let tool = OpenAIAssistantService.datetimeToolParam
        #expect(tool.function.strict == true)
    }

    @Test func datetimeToolHasNoRequiredParameters() throws {
        let tool = OpenAIAssistantService.datetimeToolParam
        let params = try #require(tool.function.parameters)
        let schema = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: schema) as? [String: Any]
        let required = json?["required"] as? [String]
        #expect(required == nil || required!.isEmpty)
    }

    // MARK: - Both tools exposed together

    @Test func apiKeyPathExposesBothTools() {
        // The ChatQuery constructed in generateWithAPIKey uses both tools.
        // Verify the static definitions are distinct and correctly named.
        let bash = OpenAIAssistantService.bashToolParam
        let datetime = OpenAIAssistantService.datetimeToolParam
        #expect(bash.function.name != datetime.function.name)
        #expect(bash.function.name == "bash")
        #expect(datetime.function.name == "datetime")
    }
}

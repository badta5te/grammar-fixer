import Foundation

/// Какой моделью и по какому адресу исправлять текст.
///
/// Настроек с интерфейсом ещё нет, они придут тикетом 06 вместе с Keychain.
/// Пока провайдер описан файлом, а переменные окружения его перекрывают —
/// так удобно пробовать другую модель, не трогая файл.
///
/// Обратный порядок был бы ошибкой: приложение запускается через `open`, и
/// переменные окружения оболочки до него не доходят. Файл здесь главный
/// именно поэтому.
public struct ProviderConfiguration: Equatable, Sendable {
    public let model: String
    public let baseURL: URL
    public let apiKey: String

    /// Расход токенов просят не все серверы понимают. Флаг позволяет выключить
    /// просьбу заранее, если сервер на неё ругается.
    public let requestsUsage: Bool

    /// Один OpenAI-совместимый путь покрывает всех, кроме Anthropic. Свой адрес
    /// задаётся полем baseURL и работает без пресета.
    static let presets = [
        "openai": "https://api.openai.com/v1",
        "deepseek": "https://api.deepseek.com/v1",
        "openrouter": "https://openrouter.ai/api/v1",
        "groq": "https://api.groq.com/openai/v1",
    ]

    static func make(
        fileContents: Data?,
        environment: [String: String],
        path: String
    ) throws -> ProviderConfiguration {
        var file = FileShape()
        if let fileContents {
            do {
                file = try JSONDecoder().decode(FileShape.self, from: fileContents)
            } catch {
                throw LLMError.brokenConfiguration(path: path, reason: error.localizedDescription)
            }
        }

        let provider = environment["GRAMMARFIXER_PROVIDER"] ?? file.provider
        let model = (environment["GRAMMARFIXER_MODEL"] ?? file.model ?? "").trimmed
        let key = (environment["GRAMMARFIXER_API_KEY"] ?? file.apiKey ?? "").trimmed
        let address = (environment["GRAMMARFIXER_BASE_URL"] ?? file.baseURL)?.trimmed

        guard !key.isEmpty else {
            // Нет файла вовсе — это первый запуск, и человеку нужно другое
            // указание, чем «допиши ключ в существующий файл».
            throw fileContents == nil
                ? LLMError.noConfiguration(path: path)
                : LLMError.noKey(path: path)
        }
        guard !model.isEmpty else {
            throw LLMError.brokenConfiguration(path: path, reason: "model is missing")
        }

        let chosen = address?.isEmpty == false
            ? address
            : provider.flatMap { presets[$0.lowercased().trimmed] }
        guard let chosen, let url = URL(string: chosen), url.scheme != nil else {
            throw LLMError.brokenConfiguration(
                path: path,
                reason: "provider is not one of \(presets.keys.sorted().joined(separator: ", ")), "
                    + "so baseURL must be set"
            )
        }

        return ProviderConfiguration(
            model: model,
            baseURL: url,
            apiKey: key,
            requestsUsage: file.requestUsage ?? true
        )
    }

    private struct FileShape: Decodable {
        var provider: String?
        var model: String?
        var apiKey: String?
        var baseURL: String?
        var requestUsage: Bool?
    }
}

/// Чтение настроек с диска. Файл перечитывается на каждом круге, чтобы смена
/// модели действовала без перезапуска.
public struct ProviderConfigurationFile: Sendable {
    public static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".config/grammar-fixer/config.json")

    /// Путь для сообщений человеку: домашний каталог в них ни к чему.
    public static var displayPath: String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    public init() {}

    /// Заготовка файла. Открывать пустоту бессмысленно, а объяснять формат
    /// в сообщении об ошибке — значит заставлять человека его перепечатывать.
    /// Неизвестные поля разбором игнорируются, поэтому подсказка живёт прямо
    /// в файле.
    @discardableResult
    public func createIfMissing() throws -> URL {
        guard !FileManager.default.fileExists(atPath: Self.url.path) else { return Self.url }
        try FileManager.default.createDirectory(
            at: Self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.template.write(to: Self.url, atomically: true, encoding: .utf8)
        // Ключ лежит открытым файлом до тикета 06 с Keychain. Права — хотя бы
        // не всем подряд.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
        return Self.url
    }

    /// Подсказка живёт прямо в файле: неизвестные поля разбором игнорируются,
    /// а объяснять формат в сообщении об ошибке — значит заставлять человека
    /// его перепечатывать.
    static let template = """
        {
          "_help": "provider: \(ProviderConfiguration.presets.keys.sorted().joined(separator: ", ")). \
        Any other OpenAI-compatible server works too: set baseURL instead of provider.",
          "provider": "openai",
          "model": "gpt-4o-mini",
          "apiKey": ""
        }

        """

    public func load() throws -> ProviderConfiguration {
        try ProviderConfiguration.make(
            fileContents: try? Data(contentsOf: Self.url),
            environment: ProcessInfo.processInfo.environment,
            path: Self.displayPath
        )
    }
}

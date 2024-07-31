// Copyright 2016 The Tulsi Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation


/// Models a configuration which can be used to generate an Xcode project directly.
public class TulsiGeneratorConfig {

  public enum ConfigError: Error {
    /// The give input file does not exist or cannot be read.
    case badInputFilePath
    /// A per-user config was found but could not be read.
    case failedToReadAdditionalOptionsData(String)
    /// Deserialization failed with the given debug info.
    case deserializationFailed(String)
    /// Serialization failed with the given debug info.
    case serializationFailed(String)
  }

  /// The file extension used when saving generator configs.
  public static let FileExtension = "tulsigen"

  /// Filename to be used when writing out user-specific values.
  public static var perUserFilename: String {
    return "\(NSUserName()).tulsigen-user"
  }

  /// The name of the Xcode project.
  public let projectName: String

  public var defaultFilename: String {
    return TulsiGeneratorConfig.sanitizeFilename("\(projectName).\(TulsiGeneratorConfig.FileExtension)")
  }

  /// The name of the Xcode project that will be generated by this config.
  public var xcodeProjectFilename: String {
    return TulsiGeneratorConfig.sanitizeFilename("\(projectName).xcodeproj")
  }

  /// The Bazel targets to generate Xcode build targets for.
  public let buildTargetLabels: [BuildLabel]

  /// The directory paths for which source files should be included in the generated Xcode project.
  public let pathFilters: Set<String>

  /// Additional file paths to add to the Xcode project (e.g., BUILD file paths).
  public let additionalFilePaths: [String]?
  /// The options for this config.
  public let options: TulsiOptionSet

  /// URL to the Bazel binary.
  private let bazelURLValue: TulsiParameter<URL>

  /// URL to the Bazel binary, computed from bazelURLValue.
  public var bazelURL: URL {
    return bazelURLValue.value
  }

  static let ProjectNameKey = "projectName"
  static let BuildTargetsKey = "buildTargets"
  static let PathFiltersKey = "sourceFilters"
  static let AdditionalFilePathsKey = "additionalFilePaths"

  /// Returns a copy of the given filename sanitized by replacing path separators and spaces.
  public static func sanitizeFilename(_ filename: String) -> String {
    return filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
  }

  // Tries to resolve a URL to the Bazel exectuable via:
  // 1. Passed in bazelURL argument.
  // 2. BazelPath set on the TulsiOptionSet.
  // 3. BazelLocator's findBazelForWorkspaceRoot.
  //
  // If none of these succeed, this returns nil.
  public static func resolveBazelURL(_ bazelURL: URL?,
                                     options: TulsiOptionSet) -> TulsiParameter<URL>? {
    if let bazelURL = bazelURL {
      return TulsiParameter(value: bazelURL, source: .explicitlyProvided)
    } else if let savedBazelPath = options[.BazelPath].commonValue {
      return TulsiParameter(value: URL(fileURLWithPath: savedBazelPath), source: .options)
    } else if let locatedURL = BazelLocator.bazelURL {
      return TulsiParameter(value: locatedURL, source: .fallback)
    }
    return nil
  }

  public static func load(_ inputFile: URL, bazelURL: URL? = nil) throws -> TulsiGeneratorConfig {
    let fileManager = FileManager.default
    guard let data = fileManager.contents(atPath: inputFile.path) else {
      throw ConfigError.badInputFilePath
    }

    let additionalOptionData: Data?
    let optionsFolderURL = inputFile.deletingLastPathComponent()
    let additionalOptionsFileURL = optionsFolderURL.appendingPathComponent(TulsiGeneratorConfig.perUserFilename)
    let perUserPath = additionalOptionsFileURL.path
    if fileManager.isReadableFile(atPath: perUserPath) {
      additionalOptionData = fileManager.contents(atPath: perUserPath)
      if additionalOptionData == nil {
        throw ConfigError.failedToReadAdditionalOptionsData("Could not read file at path \(perUserPath)")
      }
    } else {
      additionalOptionData = nil
    }

    return try TulsiGeneratorConfig(data: data,
                                    additionalOptionData: additionalOptionData,
                                    bazelURL: bazelURL)
  }

  public init(projectName: String,
              buildTargetLabels: [BuildLabel],
              pathFilters: Set<String>,
              additionalFilePaths: [String]?,
              options: TulsiOptionSet,
              bazelURL: TulsiParameter<URL>) {
    self.projectName = projectName
    self.buildTargetLabels = buildTargetLabels
    self.pathFilters = pathFilters
    self.additionalFilePaths = additionalFilePaths
    self.options = options
    self.bazelURLValue = bazelURL
  }

  public convenience init(projectName: String,
                          buildTargets: [RuleInfo],
                          pathFilters: Set<String>,
                          additionalFilePaths: [String]?,
                          options: TulsiOptionSet,
                          bazelURL: TulsiParameter<URL>) {
    self.init(projectName: projectName,
              buildTargetLabels: buildTargets.map({ $0.label }),
              pathFilters: pathFilters,
              additionalFilePaths: additionalFilePaths,
              options: options,
              bazelURL: bazelURL)
  }

  public convenience init(data: Data,
                          additionalOptionData: Data? = nil,
                          bazelURL: URL? = nil) throws {
    func extractJSONDict(_ data: Data, errorBuilder: (String) -> ConfigError) throws -> [String: AnyObject] {
      do {
        guard let jsonDict = try JSONSerialization.jsonObject(with: data,
                                                                        options: JSONSerialization.ReadingOptions()) as? [String: AnyObject] else {
          throw errorBuilder("Config file contents are invalid")
        }
        return jsonDict
      } catch let e as ConfigError {
        throw e
      } catch let e as NSError {
        throw errorBuilder(e.localizedDescription)
      } catch {
        assertionFailure("Unexpected exception")
        throw errorBuilder("Unexpected exception")
      }
    }

    let dict = try extractJSONDict(data) { ConfigError.deserializationFailed($0)}

    let projectName = dict[TulsiGeneratorConfig.ProjectNameKey] as? String ?? "Unnamed Tulsi Project"
    let buildTargetLabels = dict[TulsiGeneratorConfig.BuildTargetsKey] as? [String] ?? []
    let additionalFilePaths = dict[TulsiGeneratorConfig.AdditionalFilePathsKey] as? [String]
    let rawPathFilters = Set<String>(dict[TulsiGeneratorConfig.PathFiltersKey] as? [String] ?? [])

    // While //foo/bar is a valid filesystem path, Xcode won't open a project with such a path in
    // its structures, leading to arduous debug process.
    if let badPath = additionalFilePaths?.first(where: { $0.hasPrefix("//") }) {
      throw ConfigError.deserializationFailed("Invalid additional file path: \(badPath)")
    }


    // Convert any path filters specified as build labels to their package paths.
    var pathFilters = Set<String>()
    for sourceTarget in rawPathFilters {
      // Remap legacy tulsi includes path to the new one to preserve behavior for older projects.
      let sourceTarget = sourceTarget.replacingOccurrences(
        of: PBXTargetGenerator.legacyTulsiIncludesPath, with: PBXTargetGenerator.tulsiIncludesPath)
      if let packageName = BuildLabel(sourceTarget).packageName {
        pathFilters.insert(packageName)
      }
    }

    var optionsDict = TulsiOptionSet.getOptionsFromContainerDictionary(dict) ?? [:]
    if let additionalOptionData = additionalOptionData {
      let additionalOptions = try extractJSONDict(additionalOptionData) {
        ConfigError.failedToReadAdditionalOptionsData($0)
      }
      guard let newOptions = TulsiOptionSet.getOptionsFromContainerDictionary(additionalOptions) else {
        throw ConfigError.failedToReadAdditionalOptionsData("Invalid per-user options file")
      }
      for (key, value) in newOptions {
        optionsDict[key] = value
      }
    }
    let options = TulsiOptionSet(fromDictionary: optionsDict)

    guard let bazelURL = TulsiGeneratorConfig.resolveBazelURL(bazelURL, options: options) else {
      throw ConfigError.deserializationFailed("Unable to find Bazel Path")
    }

    self.init(projectName: projectName,
              buildTargetLabels: buildTargetLabels.map({ BuildLabel($0) }),
              pathFilters: pathFilters,
              additionalFilePaths: additionalFilePaths,
              options: options,
              bazelURL: bazelURL)
  }

  public func save() throws -> NSData {
    let sortedBuildTargetLabels = buildTargetLabels.map({ $0.value }).sorted()
    let sortedPathFilters = [String](pathFilters).sorted()
    var dict: [String: Any] = [
        TulsiGeneratorConfig.ProjectNameKey: projectName as AnyObject,
        TulsiGeneratorConfig.BuildTargetsKey: sortedBuildTargetLabels as AnyObject,
        TulsiGeneratorConfig.PathFiltersKey: sortedPathFilters as AnyObject,
    ]
    if let additionalFilePaths = additionalFilePaths {
      dict[TulsiGeneratorConfig.AdditionalFilePathsKey] = additionalFilePaths as AnyObject?
    }
    options.saveShareableOptionsIntoDictionary(&dict)

    do {
      return try JSONSerialization.tulsi_newlineTerminatedUnescapedData(jsonObject: dict,
                                                                        options: [.prettyPrinted, .sortedKeys])
    } catch let e as NSError {
      throw ConfigError.serializationFailed(e.localizedDescription)
    } catch {
      throw ConfigError.serializationFailed("Unexpected exception")
    }
  }

  public func savePerUserSettings() throws -> NSData? {
    var dict = [String: Any]()
    options.savePerUserOptionsIntoDictionary(&dict)
    if dict.isEmpty { return nil }
    do {
      return try JSONSerialization.tulsi_newlineTerminatedUnescapedData(jsonObject: dict,
                                                                        options: [.prettyPrinted, .sortedKeys])
    } catch let e as NSError {
      throw ConfigError.serializationFailed(e.localizedDescription)
    } catch {
      throw ConfigError.serializationFailed("Unexpected exception")
    }
  }

  public func configByResolvingInheritedSettingsFromProject(_ project: TulsiProject) -> TulsiGeneratorConfig {
    let resolvedOptions = options.optionSetByInheritingFrom(project.options)
    let newBazelURL = bazelURLValue.reduce(TulsiParameter(value: project.bazelURL, source: .project))
    return TulsiGeneratorConfig(projectName: projectName,
                                buildTargetLabels: buildTargetLabels,
                                pathFilters: pathFilters,
                                additionalFilePaths: additionalFilePaths,
                                options: resolvedOptions,
                                bazelURL: newBazelURL)
  }

  public func configByAppendingPathFilters(_ additionalPathFilters: Set<String>) -> TulsiGeneratorConfig {
    let newPathFilters = pathFilters.union(additionalPathFilters)
    return TulsiGeneratorConfig(projectName: projectName,
                                buildTargetLabels: buildTargetLabels,
                                pathFilters: newPathFilters,
                                additionalFilePaths: additionalFilePaths,
                                options: options,
                                bazelURL: bazelURLValue)
  }
}

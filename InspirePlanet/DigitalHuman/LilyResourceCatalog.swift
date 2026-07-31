import Foundation

struct LilyResourcePaths {
    let baseModelPath: String
    let digitalModelPath: String
}

enum LilyResourceCatalog {
    static func paths(for persona: DigitalHumanPersona, in bundle: Bundle = .main) -> LilyResourcePaths? {
        guard
            let baseURL = bundle.url(forResource: "gj_dh_res", withExtension: nil, subdirectory: "duix"),
            let digitalURL = bundle.url(
                forResource: persona.resourceFolder,
                withExtension: nil,
                subdirectory: "duix"
            )
        else {
            return nil
        }
        return LilyResourcePaths(baseModelPath: baseURL.path, digitalModelPath: digitalURL.path)
    }
}

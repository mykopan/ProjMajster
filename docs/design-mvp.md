# ProjMajster MVP Design

## Goal

ProjMajster is a Shake-based build system for projects that need more context
than raw Shake or Make rules provide. The build description should stay mostly
declarative, but still allow Haskell code and custom rules where needed.

The MVP should provide a small clean core that can later grow enough to replace
the existing Vodi build. The first supported languages are C and C++. The first
supported target shapes are programs and shared libraries.

## Non-Goals for MVP

- Static libraries as first-class targets.
- Source dependencies or subproject dependency resolution.
- pkg-config, CMake package files, vcpkg, conan, or system package integration.
- Compatibility with the current ProjMajster CLI.
- Full build/host/target compiler-toolchain modeling.
- Per-file settings implementation, although the model should not block it.

## Terminology

### Public DSL Concepts

These concepts are exposed to build authors.

- `Project`: top-level build description.
- `Target`: a buildable unit such as a program or shared library.
- `SourceSet`: a named or implicit group of source files.
- `Dependency`: an internal target dependency or external binary dependency.
- `BuildSettings`: language, compiler, linker, and common build intent.
- `BuildStyle`: a named build-settings layer such as `debug` or `release`.
- `Toolchain`: commands and translation logic for compilers/linkers.
- `InstallSpec`: where meaningful outputs should be installed or packaged.
- `Transform`: reusable build logic such as code generation, compilation, or
  linking.

### Internal Planning Concepts

These concepts are mostly internal.

- `BuildPlan`: resolved build description before Shake rules are emitted.
- `BuildRecipe`: graph of files and build steps.
- `FileRef`: a file participating in the graph, with a semantic role.
- `FileRole`: source, generated source, object, shared object, program, etc.
- `Artifact`: a meaningful output that can be used, installed, exported, or
  packaged. Not every intermediate file needs to be public artifact.

## Target Model

MVP target kinds:

```haskell
data TargetKind
  = Program
  | SharedLibrary SharedLibraryStyle
```

AORP modules are not a separate target kind. They are shared libraries with
different naming and install policy.

```haskell
data SharedLibraryStyle
  = NormalSharedLibrary
  | PluginSharedLibrary PluginStyle
```

The DSL may still provide a helper:

```haskell
aorpModule "vpw" $ do
  ...
```

but internally this should lower to a shared-library target with a specific
style.

## Platform Model

For MVP, use the project author's current mental model:

- `buildPlatform`: where the build system and build actions run.
- `targetPlatform`: where produced binaries will run.

This is enough for the current cross-build use cases.

The terminology should not prevent a later extension to the classical
`build` / `host` / `target` model for compiler-building scenarios.

## Build Styles

At minimum:

- `release`
- `debug`

Build styles are settings layers. They must not change dependencies implicitly.

For example, `debug` may set optimization and debug-info settings, but it should
not select different external packages unless the build description says so
explicitly.

Build output should be separated by platform and build style:

```text
_build/<target-platform>/<build-style>/...
```

## Settings and Flags

The user expresses build intent. Tools decide which parts apply to them.

Avoid an untyped universal flag bag as the main model. Prefer structured
settings with explicit tool ownership and an escape hatch for raw options.

Sketch:

```haskell
data BuildSettings = BuildSettings
  { commonSettings :: CommonSettings
  , cSettings      :: CSettings
  , cxxSettings    :: CxxSettings
  , linkSettings   :: LinkSettings
  , toolSettings   :: ToolSettings
  }
```

Common settings can include defines, include dirs, warning policy, debug info,
optimization, and PIC intent. C-specific settings should not leak into the
linker. Link settings should not leak into the compiler.

Raw options should be tool-scoped:

```haskell
rawCOption "-fno-strict-aliasing"
rawCxxOption "-fno-rtti"
rawLinkOption "-Wl,--as-needed"
rawToolOption "hasp-protect" "..."
```

The initial implementation may support settings only at target scope. The model
should leave room for later source-set and per-file settings.

## Dependencies

Separate logical dependencies from the mechanism used to resolve them.

Public build descriptions should say what they need. A resolver decides how to
find it.

```haskell
data ExternalDep = ExternalDep
  { depName    :: DepName
  , depVersion :: VersionReq
  , depAspects :: [DepAspect]
  , depUsage   :: DepUsage
  }
```

MVP resolver:

- remote binary package resolver, equivalent in spirit to the current remote
  package storage.

Resolved dependency sketch:

```haskell
data ResolvedDep = ResolvedDep
  { depRoot         :: FilePath
  , depIncludeDirs  :: [FilePath]
  , depLibraryDirs  :: [FilePath]
  , depRuntimeDirs  :: [FilePath]
  , depLibraries    :: [LibraryName]
  }
```

Internal target dependencies should be inferred from link usage where possible.
If a target links against a library produced by another target, the build system
should add the build dependency automatically.

Package dependencies and link libraries should remain separate concepts. A
binary package may provide many link libraries.

## Transforms

Transforms are the common model for both built-in and custom build logic. C
compile, C++ compile, link, JSON code generation, resource compilation, and
post-processing should all use the same mechanism.

Transforms should receive enough context to avoid global hacks.

Sketch:

```haskell
data RuleContext = RuleContext
  { ruleContextTargetName     :: TargetName
  , ruleContextTargetKind     :: TargetKind
  , ruleContextTargetProductBase   :: FileRef
  , ruleContextBuildPlatform  :: Platform
  , ruleContextTargetPlatform :: Platform
  , ruleContextBuildStyle     :: BuildStyle
  , ruleContextBuildDirs      :: BuildDirs
  }
```

Transforms should be reusable recipes that add build steps to the build graph.
Toolchain and dependency usage metadata can be added to this context when those
concepts become concrete. Raw Shake actions should remain available as an
escape hatch.

The Shake backend executes transform instances through a registry:

```haskell
type ShakeTransformRunner =
  RuleContext -> TransformRule -> [FileRef] -> [FileRef] -> Action ()

data CommandSpec = CommandSpec
  { commandExecutable :: FilePath
  , commandArguments  :: [String]
  , commandInputs     :: [FileRef]
  , commandOutputs    :: [FileRef]
  }

type CommandRunner =
  RuleContext -> CommandSpec -> Action ()
```

The same runner shape is used for built-in compile/link transforms and custom
transforms. A fallback runner allows the model to be tested before every real
tool invocation exists. Built-in transforms can lower to `CommandSpec` so
command construction and process execution remain separate.

At minimum, the model distinguishes:

- `MapTransform`: one input item to output item(s), for example `.json -> .c`
  or `.c -> .o`;
- `FoldTransform`: many input items to output item(s), for example objects plus
  dependency outputs to a shared library or program.

Shake execution should be manifest-driven, not static-instance-driven.
Discovered sources are only available in `Action`, so the backend should not try
to emit one Shake rule per transform instance during the `Rules` phase.

The target entrypoint should be a logical stamp such as
`_build/inter/targets/<name>/target.done`. That stamp reads the transform
manifest, discovers the real product paths produced by the transform closure,
and `need`s those products dynamically. Product file names are therefore derived
from transform rules and settings, not from `TargetKind` or the logical target
name.

Granular rebuilds are preserved by a generic output rule for build outputs. The
rule looks up the requested output in a cached transform index, `need`s only that
instance's inputs, and runs the selected transform runner. The transform manifest
should be parsed through Shake caching so repeated object-file builds do not
reparse it.

Refactoring plan:

1. Add `TransformManifest` and serialization for `TransformInstance`.
2. Add target stamp paths and product manifest paths.
3. Move transform planning from `Rules` setup into manifest-producing actions.
4. Replace `transformInstanceRules` with generic output rules plus cached
   transform-index lookup.
5. Change top-level target builds to `need` target stamps, not product paths.
6. Remove remaining assumptions that `TargetKind` determines product identity.

## Packaging and Install

Packaging should not be part of target identity.

Targets can declare install intent. A packaging layer later collects meaningful
outputs and install specs into a staging directory, archive, or upload.

This keeps shared-library build rules independent from tarball/zip/upload
policy.

## Example DSL Direction

```haskell
project "Vodi" $ do
  version [2,18,0]

  buildStyle release $ do
    optimization O2

  buildStyle debug $ do
    optimization O0
    debugInfo Full

  sharedLibrary "Vodi" $ do
    version [2,5,0]

    sources "src/lib/libVodi" $ do
      c "**/*.c"
      cxx "**/*.cpp"

    includeDirs ["src/lib/libVodi"]
    usesLibs ["Bo", "opencv_imgproc", "opencv_core", "zlib", "stdc++"]

    whenPlatform windows $ do
      usesLibs ["oldnames"]

    install runtimeLibDir

  aorpModule "vpw" $ do
    sources "src/amodules/vpw" $ do
      c "**/*.c"
      cxx "**/*.cpp"
    usesLibs ["Vodi", "Bo"]
```

## Open Questions

1. What should the first remote binary package descriptor look like?
2. Should external deps be declared globally and then referenced by targets, or
   declared directly in each target?
3. How much source discovery should be built into the DSL versus left to user
   Haskell code?
4. What is the minimum custom-transform API needed to express existing Vodi
   generators cleanly?
5. Should install specs be part of MVP, or only modeled and implemented after
   compile/link works?

## Proposed Implementation Order

1. Define core data types for project, target, source set, settings, build styles,
   dependencies, and platform context.
2. Implement planning from DSL declarations into a `BuildPlan`.
3. Implement source discovery and transform-based graph lowering.
4. Implement built-in C/C++ compile and link transforms.
5. Add remote binary dependency resolver.
6. Add install intent and minimal staging/package support.
7. Port a small Vodi subset.
8. Expand until the full Vodi build can move over.

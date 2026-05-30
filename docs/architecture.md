# ProjMajster Architecture

This document maps the MVP design to Haskell modules and data flow. Shake is
the execution engine, not merely a Make-like file-rule syntax. The architecture
should use Shake's strengths: dynamic dependencies, tracked directory queries,
generated dependency files, caches, oracles, parallelism, and minimal rebuilds.

## Data Flow

ProjMajster should have three explicit phases:

```text
DSL declarations
  -> validation and resolution
  -> BuildPlan
  -> BuildGraph
  -> Shake rules
```

The public DSL should collect intent. It should not emit Shake rules directly.
Shake integration should happen only after the build has been resolved into an
internal plan.

`BuildPlan` is mostly static: it contains resolved targets, settings,
dependency declarations, and toolchain choices. `BuildGraph` is concrete enough
to emit Shake rules, but it must not pretend that every dependency is known
up front. Some dependencies are discovered during Shake actions, for example C
and C++ header dependencies emitted by the compiler.

The backend should therefore preserve two kinds of dependencies:

- planned dependencies: files and targets known before rules run;
- discovered dependencies: files, directory contents, or oracle answers found
  while running an action and then recorded by Shake.

## Layer Boundaries

### DSL Layer

Purpose:

- Provide user-facing combinators such as `project`, `program`,
  `sharedLibrary`, `sources`, `usesLibs`, `buildStyle`, and `install`.
- Collect declarations in a mostly declarative form.
- Allow Haskell conditionals and custom logic.

Must not:

- Run compiler/linker commands.
- Resolve remote dependencies.
- Know Shake implementation details.
- Decide final object or binary paths.

Suggested modules:

```text
ProjMajster
ProjMajster.DSL
ProjMajster.DSL.Project
ProjMajster.DSL.Target
ProjMajster.DSL.Settings
ProjMajster.DSL.Dependency
```

### Core Model

Purpose:

- Define stable domain types shared by all layers.
- Keep types independent from Shake where possible.

Suggested modules:

```text
ProjMajster.Core.Platform
ProjMajster.Core.BuildStyle
ProjMajster.Core.Project
ProjMajster.Core.Target
ProjMajster.Core.SourceSet
ProjMajster.Core.Settings
ProjMajster.Core.Dependency
ProjMajster.Core.Install
ProjMajster.Core.FileRole
```

### Planning Layer

Purpose:

- Validate DSL declarations.
- Resolve settings layers.
- Resolve static source-set declarations.
- Resolve internal target dependencies.
- Ask dependency resolvers for external binary dependencies.
- Produce a `BuildPlan`.

Must not:

- Emit Shake rules directly.
- Run compile/link actions.
- Depend on generated files discovered during the same build.

Source discovery has two modes:

- static discovery during planning, for sources that are intentionally fixed;
- Shake-tracked discovery in the backend, for globbed source sets that should
  rebuild when files are added or removed.

Use Shake-tracked discovery for normal source globs. Do not scan generated
output directories as source directories, because those contents can change
while the build is running.

Suggested modules:

```text
ProjMajster.Plan
ProjMajster.Plan.Resolve
ProjMajster.Plan.Validate
ProjMajster.Plan.SourceDiscovery
ProjMajster.Plan.InternalDeps
ProjMajster.Plan.Settings
```

### Build Graph Layer

Purpose:

- Lower `BuildPlan` into concrete file nodes and build steps.
- Decide intermediate output paths.
- Attach file roles and target ownership.
- Apply transform rules such as JSON code generation, C compile, C++ compile,
  link program, link shared library, and custom project-specific generation.
- Represent which dependencies are planned and which will be discovered by the
  backend.

Compile and link are not special graph concepts. They are built-in transform
rules. Custom transforms use the same representation.

Suggested modules:

```text
ProjMajster.Graph
ProjMajster.Graph.FileRef
ProjMajster.Graph.Step
ProjMajster.Graph.Transform
ProjMajster.Graph.Layout
```

### Toolchain Layer

Purpose:

- Represent compilers, linkers, and related tools.
- Translate structured settings into command-line arguments.
- Define file naming policies for platforms and shared-library styles.

Suggested modules:

```text
ProjMajster.Toolchain
ProjMajster.Toolchain.C
ProjMajster.Toolchain.Cxx
ProjMajster.Toolchain.Linker
ProjMajster.Toolchain.GCC
ProjMajster.Toolchain.Clang
ProjMajster.Toolchain.MSVC
ProjMajster.Toolchain.Default
```

Toolchain code may know about platforms and build styles. It should not know
about remote package storage or final packaging policy.

### Dependency Resolution Layer

Purpose:

- Resolve logical external dependencies to include dirs, library dirs, runtime
  dirs, and available libraries.
- Provide the initial remote binary package resolver.

Suggested modules:

```text
ProjMajster.Deps
ProjMajster.Deps.Resolver
ProjMajster.Deps.RemoteBinary
ProjMajster.Deps.Resolved
```

Dependency resolution should be independent from target kinds. A resolved
dependency is just build/link/runtime information.

### Install and Packaging Layer

Purpose:

- Interpret install specs.
- Build a staging directory.
- Later create archives or upload them.

Suggested modules:

```text
ProjMajster.Install
ProjMajster.Install.Plan
ProjMajster.Package
ProjMajster.Package.Archive
ProjMajster.Package.Upload
```

This layer should consume target outputs and install specs. It should not be
part of target identity.

### Shake Backend

Purpose:

- Convert the build graph to Shake rules.
- Provide caches, change tracking, and command execution.
- Use Shake-tracked source discovery for source globs.
- Record compiler-discovered dependencies such as C/C++ headers.
- Provide custom rules/oracles for non-file dependencies when needed.
- Keep Shake-specific code contained.

Suggested modules:

```text
ProjMajster.Backend.Shake
ProjMajster.Backend.Shake.Rules
ProjMajster.Backend.Shake.Command
ProjMajster.Backend.Shake.Oracle
```

The backend is allowed to expose `Action` to low-level transform
implementations. The public DSL should not require users to write `Action`
code for common cases, but advanced custom transforms need that escape hatch.

The backend should prefer Shake primitives for correctness:

- `need` for planned file dependencies;
- tracked directory queries for source globs;
- makefile-style dependency loading for C/C++ header dependencies;
- caches for expensive pure or action-based lookups;
- oracles for dependencies on non-file facts such as compiler version,
  toolchain probe results, or remote package metadata.

## Key Types Sketch

```haskell
data BuildContext = BuildContext
  { buildPlatform  :: Platform
  , targetPlatform :: Platform
  , contextBuildStyle :: BuildStyle
  , contextBuildDirs :: BuildDirs
  , toolchain      :: Toolchain
  }

data BuildPlan = BuildPlan
  { planContext      :: BuildContext
  , planTargets      :: [ResolvedTarget]
  , planExternalDeps :: [ResolvedDep]
  , planInstallSpecs :: [ResolvedInstallSpec]
  }

data BuildGraph = BuildGraph
  { graphSources :: [SourceDiscovery]
  , graphTargets :: [TargetBuild]
  }

data SourceDiscovery = SourceDiscovery
  { sourceDiscoveryOwner :: TargetName
  , sourceDiscoveryGlob  :: SourceGlob
  }

data TargetBuild = TargetBuild
  { targetBuildName         :: TargetName
  , targetBuildKind         :: TargetKind
  , targetBuildSources      :: [SourceDiscovery]
  , targetBuildTransforms   :: [TransformRule]
  , targetBuildDependencies :: [TargetName]
  , targetBuildOutput       :: FileRef
  }

data TransformRule = TransformRule
  { transformName   :: TransformName
  , transformKind   :: TransformKind
  , transformInput  :: InputSelector
  , transformOutput :: OutputMapping
  , transformAction :: TransformAction
  }

data TransformKind
  = MapTransform
  | FoldTransform
```

The exact representation can change, but the distinction should remain:
`BuildGraph` is a declarative graph of source discovery and target transform
pipelines. Backend-specific execution instances are derived later.

Examples:

```text
json-to-c  : MapTransform  JSON source -> generated C source
compile-c  : MapTransform  C source -> object file
compile-cxx: MapTransform  C++ source -> object file
link       : FoldTransform object files + dependency outputs -> target binary
```

## Error Strategy

Prefer early validation errors during planning:

- duplicate target names;
- unknown internal dependency;
- unsupported source language;
- missing toolchain component;
- unresolved external dependency;
- ambiguous link library that could refer to multiple internal targets;
- invalid settings for selected toolchain/platform.

Shake-time failures should mostly be real execution failures, not configuration
errors that could have been detected earlier.

Some dependencies can only be validated at Shake time. Examples:

- a generated makefile dependency file is malformed;
- a compiler reports headers after preprocessing;
- a source glob changes between builds;
- an oracle query depends on the installed toolchain.

These are legitimate Shake-time concerns and should be handled in backend or
transform code.

## MVP Implementation Milestones

1. Core types compile.
2. DSL can declare a project with one shared library and one program.
3. Planning validates declarations and resolves settings.
4. Graph lowering applies built-in and custom transform rules with
   planned/discovered dependency metadata.
5. Shake backend can run those steps.
6. C/C++ compile transforms record generated header dependencies.
7. Shake-tracked source globs rebuild when source files are added or removed.
8. Internal dependency inference works through `usesLibs`.
9. Remote binary dependency resolver provides include/library dirs.
10. Minimal install staging works.
11. A small Vodi subset builds.

## Design Rules

- Public DSL should express user intent, not internal file mechanics.
- Tool settings must be scoped to the tool that consumes them.
- Build styles must not change dependencies implicitly.
- Target kind and install/package policy must remain separate.
- External dependency identity and dependency resolution mechanism must remain
  separate.
- Shake should be a backend detail, not the core domain model.
- Do not force all dependencies to be known during planning. Use Shake dynamic
  dependencies where that is the correct model.
- Common users should not need to understand Shake, but advanced transforms
  should be able to use Shake `Action` deliberately.
- Built-in C/C++ compile and link behavior should be represented as transform
  rules, not as a separate mechanism from custom transforms.

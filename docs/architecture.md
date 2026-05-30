# ProjMajster Architecture

This document maps the MVP design to Haskell modules and data flow.

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
- Resolve source sets into source files.
- Resolve internal target dependencies.
- Ask dependency resolvers for external binary dependencies.
- Produce a `BuildPlan`.

Must not:

- Emit Shake rules directly.
- Run compile/link actions.

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
- Apply transforms such as C compile, C++ compile, link program, link shared
  library, and custom code generation.

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
- Keep Shake-specific code contained.

Suggested modules:

```text
ProjMajster.Backend.Shake
ProjMajster.Backend.Shake.Rules
ProjMajster.Backend.Shake.Command
```

## Key Types Sketch

```haskell
data BuildContext = BuildContext
  { buildPlatform  :: Platform
  , targetPlatform :: Platform
  , buildStyle     :: BuildStyle
  , buildDirs      :: BuildDirs
  , toolchain      :: Toolchain
  }

data BuildPlan = BuildPlan
  { planContext      :: BuildContext
  , planTargets      :: [ResolvedTarget]
  , planExternalDeps :: [ResolvedDep]
  , planInstallSpecs :: [ResolvedInstallSpec]
  }

data BuildGraph = BuildGraph
  { graphFiles :: [FileRef]
  , graphSteps :: [BuildStep]
  }

data BuildStep = BuildStep
  { stepName    :: StepName
  , stepInputs  :: [FileRef]
  , stepOutputs :: [FileRef]
  , stepAction  :: StepAction
  }
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

## MVP Implementation Milestones

1. Core types compile.
2. DSL can declare a project with one shared library and one program.
3. Planning validates declarations and resolves settings.
4. Graph lowering produces compile and link steps.
5. Shake backend can run those steps.
6. Internal dependency inference works through `usesLibs`.
7. Remote binary dependency resolver provides include/library dirs.
8. Minimal install staging works.
9. A small Vodi subset builds.

## Design Rules

- Public DSL should express user intent, not internal file mechanics.
- Tool settings must be scoped to the tool that consumes them.
- Build styles must not change dependencies implicitly.
- Target kind and install/package policy must remain separate.
- External dependency identity and dependency resolution mechanism must remain
  separate.
- Shake should be a backend detail, not the core domain model.

module ProjMajster.Graph.Build
  ( buildGraph
  ) where

import qualified Data.Text as Text
import System.FilePath ((</>), (<.>))

import ProjMajster.Core
import ProjMajster.Graph.Types
import ProjMajster.Plan.Types

buildGraph :: BuildPlan -> BuildGraph
buildGraph plan = BuildGraph
  { graphSources = concatMap targetBuildSources targets
  , graphTargets = targets
  }
  where
    targets =
      map (targetBuild (planContext plan)) (planTargets plan)

targetBuild :: BuildContext -> ResolvedTarget -> TargetBuild
targetBuild context target = TargetBuild
  { targetBuildName = resolvedTargetName target
  , targetBuildKind = resolvedTargetKind target
  , targetBuildSources = sourceDiscoveries (resolvedTargetName target) target
  , targetBuildTransforms = resolvedTargetTransforms target
  , targetBuildDependencies = internalDependencies target
  , targetBuildOutput = targetOutput context target
  }

sourceDiscoveries :: TargetName -> ResolvedTarget -> [SourceDiscovery]
sourceDiscoveries owner target =
  [ SourceDiscovery
      { sourceDiscoveryOwner = owner
      , sourceDiscoveryGlob = SourceGlob
          { sourceGlobBaseDir = sourcePatternBaseDir pattern
          , sourceGlobPattern = sourcePatternGlob pattern
          , sourceGlobLanguage = sourcePatternLanguage pattern
          }
      }
  | sourceSet <- resolvedTargetSourceSets target
  , pattern <- sourceSetPatterns sourceSet
  ]

internalDependencies :: ResolvedTarget -> [TargetName]
internalDependencies target =
  [ depTarget
  | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
  ]

targetOutput :: BuildContext -> ResolvedTarget -> FileRef
targetOutput context target = FileRef
  { fileRefPath =
      buildProductDir (contextBuildDirs context) </> targetOutputName target
  , fileRefRole = outputRole (resolvedTargetKind target)
  , fileRefLanguage = Nothing
  , fileRefOwner = Just (resolvedTargetName target)
  }

targetOutputName :: ResolvedTarget -> FilePath
targetOutputName target =
  case resolvedTargetKind target of
    Program ->
      targetNameString (resolvedTargetName target)
    SharedLibrary _ ->
      "lib" <> targetNameString (resolvedTargetName target) <.> "so"

outputRole :: TargetKind -> FileRole
outputRole Program = ProgramBinary
outputRole (SharedLibrary _) = SharedObject

targetNameString :: TargetName -> String
targetNameString (TargetName name) =
  Text.unpack name

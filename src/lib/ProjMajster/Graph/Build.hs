{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Graph.Build
  ( buildGraph
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import System.FilePath ((</>), (<.>), takeBaseName)

import ProjMajster.Core
import ProjMajster.Graph.Types
import ProjMajster.Plan.Types

buildGraph :: BuildPlan -> BuildGraph
buildGraph plan = BuildGraph
  { graphFiles = graphFiles'
  , graphSteps = discoverySteps <> compileSteps <> linkSteps
  }
  where
    outputsByTarget = Map.fromList
      [ (resolvedTargetName target, targetOutputs (planContext plan) target)
      | target <- planTargets plan
      ]
    targetGraphs =
      map (targetGraph (planContext plan) outputsByTarget) (planTargets plan)
    discoverySteps = concatMap tgDiscoverySteps targetGraphs
    compileSteps = concatMap tgCompileSteps targetGraphs
    linkSteps = concatMap tgLinkSteps targetGraphs
    graphFiles' =
      concatMap tgFiles targetGraphs

data TargetGraph = TargetGraph
  { tgFiles :: [FileRef]
  , tgDiscoverySteps :: [BuildStep]
  , tgCompileSteps :: [BuildStep]
  , tgLinkSteps :: [BuildStep]
  }

targetGraph
  :: BuildContext
  -> Map.Map TargetName [FileRef]
  -> ResolvedTarget
  -> TargetGraph
targetGraph context outputsByTarget target = TargetGraph
  { tgFiles = sourceRefs <> objectRefs <> outputRefs
  , tgDiscoverySteps = map (sourceDiscoveryStep targetName') patterns
  , tgCompileSteps =
      zipWith (compileStep context targetName') patterns objectRefs
  , tgLinkSteps =
      [linkStep target output (objectRefs <> dependencyOutputRefs)
      | output <- outputRefs
      ]
  }
  where
    targetName' = resolvedTargetName target
    patterns =
      [ pattern
      | sourceSet <- resolvedTargetSourceSets target
      , pattern <- sourceSetPatterns sourceSet
      ]
    sourceRefs = map (sourceFileRef targetName') patterns
    objectRefs = map (objectFileRef context targetName') patterns
    outputRefs = targetOutputs context target
    dependencyOutputRefs =
      concat
        [ Map.findWithDefault [] depTarget outputsByTarget
        | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
        ]

sourceDiscoveryStep :: TargetName -> SourcePattern -> BuildStep
sourceDiscoveryStep owner pattern = BuildStep
  { buildStepName =
      StepName ("discover-sources:" <> targetNameText owner <> ":" <> patternText pattern)
  , buildStepInputs = []
  , buildStepOutputs = [sourceFileRef owner pattern]
  , buildStepDiscovered =
      [ DiscoverSourceGlob SourceGlob
          { sourceGlobBaseDir = sourcePatternBaseDir pattern
          , sourceGlobPattern = sourcePatternGlob pattern
          , sourceGlobLanguage = sourcePatternLanguage pattern
          }
      ]
  , buildStepAction = DiscoverSources
  }

compileStep :: BuildContext -> TargetName -> SourcePattern -> FileRef -> BuildStep
compileStep context owner pattern objectRef = BuildStep
  { buildStepName =
      StepName ("compile:" <> targetNameText owner <> ":" <> patternText pattern)
  , buildStepInputs = [sourceFileRef owner pattern]
  , buildStepOutputs = [objectRef]
  , buildStepDiscovered =
      [DiscoverMakefileDeps (depFilePath context owner pattern)]
  , buildStepAction = Compile (sourcePatternLanguage pattern)
  }

linkStep :: ResolvedTarget -> FileRef -> [FileRef] -> BuildStep
linkStep target output objects = BuildStep
  { buildStepName =
      StepName ("link:" <> targetNameText (resolvedTargetName target))
  , buildStepInputs = objects
  , buildStepOutputs = [output]
  , buildStepDiscovered = []
  , buildStepAction = Link
  }

sourceFileRef :: TargetName -> SourcePattern -> FileRef
sourceFileRef owner pattern = FileRef
  { fileRefPath = sourcePatternBaseDir pattern </> sourcePatternGlob pattern
  , fileRefRole = SourceFile
  , fileRefOwner = Just owner
  }

objectFileRef :: BuildContext -> TargetName -> SourcePattern -> FileRef
objectFileRef context owner pattern = FileRef
  { fileRefPath =
      targetInterDir context owner </> objectPatternBase pattern <.> "o"
  , fileRefRole = ObjectFile
  , fileRefOwner = Just owner
  }

targetOutputs :: BuildContext -> ResolvedTarget -> [FileRef]
targetOutputs context target =
  [ FileRef
      { fileRefPath =
          buildProductDir (contextBuildDirs context) </> targetOutputName target
      , fileRefRole = outputRole (resolvedTargetKind target)
      , fileRefOwner = Just (resolvedTargetName target)
      }
  ]

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

depFilePath :: BuildContext -> TargetName -> SourcePattern -> FilePath
depFilePath context owner pattern =
  targetInterDir context owner </> objectPatternBase pattern <.> "d"

targetInterDir :: BuildContext -> TargetName -> FilePath
targetInterDir context owner =
  buildInterDir (contextBuildDirs context) </> targetNameString owner

objectPatternBase :: SourcePattern -> FilePath
objectPatternBase pattern =
  languageDir (sourcePatternLanguage pattern) </> takeBaseName (sourcePatternGlob pattern)

languageDir :: Language -> FilePath
languageDir C = "c"
languageDir Cxx = "cxx"
languageDir (CustomLanguage name) = "custom-" <> Text.unpack name

patternText :: SourcePattern -> Text
patternText pattern =
  Text.pack (sourcePatternBaseDir pattern </> sourcePatternGlob pattern)

targetNameString :: TargetName -> String
targetNameString =
  Text.unpack . targetNameText

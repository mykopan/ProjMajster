{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Graph.Build
  ( buildGraph
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import System.FilePath ((</>), (<.>), takeBaseName, takeDirectory)

import ProjMajster.Core
import ProjMajster.Graph.Types
import ProjMajster.Plan.Types

buildGraph :: BuildPlan -> BuildGraph
buildGraph plan = BuildGraph
  { graphFiles = graphFiles'
  , graphSteps = discoverySteps <> transformSteps
  }
  where
    outputsByTarget = Map.fromList
      [ (resolvedTargetName target, targetOutputs (planContext plan) target)
      | target <- planTargets plan
      ]
    targetGraphs =
      map (targetGraph (planContext plan) outputsByTarget) (planTargets plan)
    discoverySteps = concatMap tgDiscoverySteps targetGraphs
    transformSteps = concatMap tgTransformSteps targetGraphs
    graphFiles' =
      concatMap tgFiles targetGraphs

data TargetGraph = TargetGraph
  { tgFiles :: [FileRef]
  , tgDiscoverySteps :: [BuildStep]
  , tgTransformSteps :: [BuildStep]
  }

targetGraph
  :: BuildContext
  -> Map.Map TargetName [FileRef]
  -> ResolvedTarget
  -> TargetGraph
targetGraph context outputsByTarget target = TargetGraph
  { tgFiles = finalRefs
  , tgDiscoverySteps = map (sourceDiscoveryStep targetName') patterns
  , tgTransformSteps = steps
  }
  where
    targetName' = resolvedTargetName target
    patterns =
      [ pattern
      | sourceSet <- resolvedTargetSourceSets target
      , pattern <- sourceSetPatterns sourceSet
      ]
    sourceRefs = map (sourceFileRef targetName') patterns
    dependencyOutputRefs =
      concat
        [ Map.findWithDefault [] depTarget outputsByTarget
        | InternalDependency (InternalDep depTarget) <- resolvedTargetDeps target
        ]
    TransformResult finalRefs steps =
      applyTransforms context target dependencyOutputRefs sourceRefs

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
  , buildStepTransform = discoverSourcesTransform
  }

data TransformResult = TransformResult [FileRef] [BuildStep]

applyTransforms
  :: BuildContext
  -> ResolvedTarget
  -> [FileRef]
  -> [FileRef]
  -> TransformResult
applyTransforms context target dependencyOutputRefs initialRefs =
  foldl apply (TransformResult initialRefs []) (resolvedTargetTransforms target)
  where
    apply (TransformResult refs steps) rule =
      case transformKind rule of
        MapTransform ->
          let inputs = filter (matchesInput (transformInput rule)) refs
              newSteps = map (mapTransformStep context target rule) inputs
              newRefs = concatMap buildStepOutputs newSteps
          in TransformResult (refs <> newRefs) (steps <> newSteps)
        FoldTransform ->
          let inputs = filter (matchesInput (transformInput rule))
                (refs <> dependencyOutputRefs)
              newStep = foldTransformStep context target rule inputs
              newRefs = buildStepOutputs newStep
          in TransformResult (refs <> newRefs) (steps <> [newStep])

matchesInput :: InputSelector -> FileRef -> Bool
matchesInput selector file =
  case selector of
    InputLanguage language ->
      fileRefLanguage file == Just language
    InputRole role ->
      fileRefRole file == role
    InputAnyObject ->
      fileRefRole file == ObjectFile
    InputLinkInput ->
      fileRefRole file `elem` [ObjectFile, SharedObject, ProgramBinary]
    InputAny ->
      True

mapTransformStep
  :: BuildContext
  -> ResolvedTarget
  -> TransformRule
  -> FileRef
  -> BuildStep
mapTransformStep context target rule input = BuildStep
  { buildStepName =
      StepName
        ( transformNameText (transformName rule)
        <> ":"
        <> targetNameText (resolvedTargetName target)
        <> ":"
        <> Text.pack (fileRefPath input)
        )
  , buildStepInputs = [input]
  , buildStepOutputs = [mapTransformOutput context target rule input]
  , buildStepDiscovered = mapTransformDiscovery context target rule input
  , buildStepTransform = rule
  }

foldTransformStep
  :: BuildContext
  -> ResolvedTarget
  -> TransformRule
  -> [FileRef]
  -> BuildStep
foldTransformStep context target rule inputs = BuildStep
  { buildStepName =
      StepName
        ( transformNameText (transformName rule)
        <> ":"
        <> targetNameText (resolvedTargetName target)
        )
  , buildStepInputs = inputs
  , buildStepOutputs = [foldTransformOutput context target rule]
  , buildStepDiscovered = []
  , buildStepTransform = rule
  }

mapTransformOutput
  :: BuildContext
  -> ResolvedTarget
  -> TransformRule
  -> FileRef
  -> FileRef
mapTransformOutput context target rule input =
  case transformOutput rule of
    OutputObject ->
      FileRef
        { fileRefPath =
            targetInterDir context (resolvedTargetName target)
              </> "obj"
              </> takeBaseName (fileRefPath input)
              <.> "o"
        , fileRefRole = ObjectFile
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (resolvedTargetName target)
        }
    OutputGeneratedSource language suffix ->
      FileRef
        { fileRefPath =
            targetInterDir context (resolvedTargetName target)
              </> "generated"
              </> takeDirectory (fileRefPath input)
              </> takeBaseName (fileRefPath input) <> suffix
        , fileRefRole = GeneratedSource
        , fileRefLanguage = Just language
        , fileRefOwner = Just (resolvedTargetName target)
        }
    OutputTargetBinary ->
      foldTransformOutput context target rule
    OutputCustom role suffix ->
      FileRef
        { fileRefPath =
            targetInterDir context (resolvedTargetName target)
              </> "custom"
              </> takeBaseName (fileRefPath input) <> suffix
        , fileRefRole = role
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (resolvedTargetName target)
        }

foldTransformOutput :: BuildContext -> ResolvedTarget -> TransformRule -> FileRef
foldTransformOutput context target rule =
  case transformOutput rule of
    OutputTargetBinary ->
      targetOutput context target
    OutputCustom role suffix ->
      FileRef
        { fileRefPath =
            targetInterDir context (resolvedTargetName target)
              </> Text.unpack (transformNameText (transformName rule)) <> suffix
        , fileRefRole = role
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (resolvedTargetName target)
        }
    OutputObject ->
      targetOutput context target
    OutputGeneratedSource language suffix ->
      FileRef
        { fileRefPath =
            targetInterDir context (resolvedTargetName target)
              </> Text.unpack (transformNameText (transformName rule)) <> suffix
        , fileRefRole = GeneratedSource
        , fileRefLanguage = Just language
        , fileRefOwner = Just (resolvedTargetName target)
        }

mapTransformDiscovery
  :: BuildContext
  -> ResolvedTarget
  -> TransformRule
  -> FileRef
  -> [Discovery]
mapTransformDiscovery context target rule input =
  case transformAction rule of
    BuiltinAction BuiltinCompileC ->
      [DiscoverMakefileDeps (depFilePath context target input)]
    BuiltinAction BuiltinCompileCxx ->
      [DiscoverMakefileDeps (depFilePath context target input)]
    BuiltinAction BuiltinLink ->
      []
    CustomAction _ ->
      []

sourceFileRef :: TargetName -> SourcePattern -> FileRef
sourceFileRef owner pattern = FileRef
  { fileRefPath = sourcePatternBaseDir pattern </> sourcePatternGlob pattern
  , fileRefRole = SourceFile
  , fileRefLanguage = Just (sourcePatternLanguage pattern)
  , fileRefOwner = Just owner
  }

targetOutputs :: BuildContext -> ResolvedTarget -> [FileRef]
targetOutputs context target = [targetOutput context target]

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

depFilePath :: BuildContext -> ResolvedTarget -> FileRef -> FilePath
depFilePath context target input =
  targetInterDir context (resolvedTargetName target)
    </> "deps"
    </> takeBaseName (fileRefPath input)
    <.> "d"

targetInterDir :: BuildContext -> TargetName -> FilePath
targetInterDir context owner =
  buildInterDir (contextBuildDirs context) </> targetNameString owner

patternText :: SourcePattern -> Text
patternText pattern =
  Text.pack (sourcePatternBaseDir pattern </> sourcePatternGlob pattern)

targetNameString :: TargetName -> String
targetNameString =
  Text.unpack . targetNameText

discoverSourcesTransform :: TransformRule
discoverSourcesTransform = TransformRule
  { transformName = TransformName "discover-sources"
  , transformKind = MapTransform
  , transformInput = InputAny
  , transformOutput = OutputCustom SourceFile ""
  , transformAction = CustomAction "discover-sources"
  }

module ProjMajster.Backend.Shake.Transform
  ( TransformInstance(..)
  , planMapTransforms
  , planTargetTransforms
  , transformInstanceRules
  ) where

import Data.List (sort)
import qualified Data.Text as Text
import qualified Data.Set as Set
import Development.Shake
import System.FilePath ((</>), (<.>), dropExtension, splitDirectories, takeDirectory)
import qualified System.Directory as Directory

import ProjMajster.Backend.Shake.SourceDiscovery
import ProjMajster.Core
import ProjMajster.Recipe

data TransformInstance = TransformInstance
  { transformInstanceTarget :: TargetName
  , transformInstanceRuleContext :: RuleContext
  , transformInstanceRule :: TransformRule
  , transformInstanceInputs :: [FileRef]
  , transformInstanceOutputs :: [FileRef]
  } deriving (Eq, Show)

transformInstanceRules :: [TransformInstance] -> Rules ()
transformInstanceRules =
  mapM_ transformInstanceBuildRules

transformInstanceBuildRules :: TransformInstance -> Rules ()
transformInstanceBuildRules instance_ =
  mapM_ (`transformInstanceOutputRule` instance_) (transformInstanceOutputs instance_)

transformInstanceOutputRule :: FileRef -> TransformInstance -> Rules ()
transformInstanceOutputRule output instance_ =
  fileRefPath output %> \outputPath -> do
    need (map fileRefPath (transformInstanceInputs instance_))
    liftIO $ Directory.createDirectoryIfMissing True (takeDirectory outputPath)
    writeFileChanged outputPath (transformInstanceStamp instance_ output)

transformInstanceStamp :: TransformInstance -> FileRef -> String
transformInstanceStamp instance_ output = unlines $
  [ "transform: " <> transformNameString (transformName (transformInstanceRule instance_))
  , "target: " <> targetNameString (transformInstanceTarget instance_)
  , "output: " <> fileRefPath output
  , "inputs:"
  ] <>
  [ "- " <> fileRefPath input
  | input <- transformInstanceInputs instance_
  ]

transformNameString :: TransformName -> String
transformNameString (TransformName name) =
  Text.unpack name

planTargetTransforms
  :: BuildContext
  -> TargetRecipe
  -> [DiscoveredSource]
  -> [FileRef]
  -> [TransformInstance]
planTargetTransforms context target discovered dependencyOutputs =
  mapInstances <> foldInstances
  where
    mapInstances =
      planMapTransforms context target discovered
    knownFiles =
      targetSourceRefs target discovered <>
      concatMap transformInstanceOutputs mapInstances <>
      dependencyOutputs
    foldInstances =
      planFoldTransforms context target knownFiles

planMapTransforms
  :: BuildContext
  -> TargetRecipe
  -> [DiscoveredSource]
  -> [TransformInstance]
planMapTransforms context target discovered =
  go Set.empty sourceRefs []
  where
    sourceRefs = targetSourceRefs target discovered
    mapRules =
      filter ((MapTransform ==) . transformKind) (targetRecipeTransforms target)

    go seen refs instances =
      case newInstances seen refs of
        [] ->
          instances
        xs ->
          let seen' = seen <> Set.fromList (map transformInstanceKey xs)
              refs' = refs <> concatMap transformInstanceOutputs xs
          in go seen' refs' (instances <> xs)

    newInstances seen refs =
      [ instance_
      | rule <- mapRules
      , input <- refs
      , matchesInput (transformInput rule) input
      , let instance_ = mapTransformInstance context target rule input
      , transformInstanceKey instance_ `Set.notMember` seen
      ]

type TransformInstanceKey = (TransformName, FilePath)

transformInstanceKey :: TransformInstance -> TransformInstanceKey
transformInstanceKey instance_ =
  ( transformName (transformInstanceRule instance_)
  , case transformInstanceInputs instance_ of
      input : _ -> fileRefPath input
      [] -> ""
  )

type FoldTransformInstanceKey = (TransformName, [FilePath])

foldTransformInstanceKey :: TransformInstance -> FoldTransformInstanceKey
foldTransformInstanceKey instance_ =
  ( transformName (transformInstanceRule instance_)
  , sort (map fileRefPath (transformInstanceInputs instance_))
  )

planFoldTransforms
  :: BuildContext
  -> TargetRecipe
  -> [FileRef]
  -> [TransformInstance]
planFoldTransforms context target refs =
  go Set.empty []
  where
    foldRules =
      filter ((FoldTransform ==) . transformKind) (targetRecipeTransforms target)

    go seen instances =
      case newInstances seen of
        [] -> instances
        xs ->
          let seen' = seen <> Set.fromList (map foldTransformInstanceKey xs)
          in go seen' (instances <> xs)

    newInstances seen =
      [ instance_
      | rule <- foldRules
      , let inputs = filter (matchesInput (transformInput rule)) refs
      , not (null inputs)
      , let instance_ = foldTransformInstance context target rule inputs
      , foldTransformInstanceKey instance_ `Set.notMember` seen
      ]

mapTransformInstance
  :: BuildContext
  -> TargetRecipe
  -> TransformRule
  -> FileRef
  -> TransformInstance
mapTransformInstance context target rule input = TransformInstance
  { transformInstanceTarget = targetRecipeName target
  , transformInstanceRuleContext = ruleContext context target
  , transformInstanceRule = rule
  , transformInstanceInputs = [input]
  , transformInstanceOutputs =
      [mapTransformOutput context target rule input]
  }

foldTransformInstance
  :: BuildContext
  -> TargetRecipe
  -> TransformRule
  -> [FileRef]
  -> TransformInstance
foldTransformInstance context target rule inputs = TransformInstance
  { transformInstanceTarget = targetRecipeName target
  , transformInstanceRuleContext = ruleContext context target
  , transformInstanceRule = rule
  , transformInstanceInputs = inputs
  , transformInstanceOutputs = [foldTransformOutput target rule]
  }

ruleContext :: BuildContext -> TargetRecipe -> RuleContext
ruleContext context target = RuleContext
  { ruleContextTargetName = targetRecipeName target
  , ruleContextTargetKind = targetRecipeKind target
  , ruleContextTargetOutput = targetRecipeOutput target
  , ruleContextBuildPlatform = buildPlatform context
  , ruleContextTargetPlatform = targetPlatform context
  , ruleContextBuildStyle = contextBuildStyle context
  , ruleContextBuildDirs = contextBuildDirs context
  }

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

mapTransformOutput
  :: BuildContext
  -> TargetRecipe
  -> TransformRule
  -> FileRef
  -> FileRef
mapTransformOutput context target rule input =
  case transformOutput rule of
    OutputObject ->
      FileRef
        { fileRefPath =
            targetInterDir context (targetRecipeName target)
              </> "obj"
              </> normalizedObjectPath input
              <.> "o"
        , fileRefRole = ObjectFile
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (targetRecipeName target)
        }
    OutputGeneratedSource language suffix ->
      FileRef
        { fileRefPath =
            targetInterDir context (targetRecipeName target)
              </> "generated"
              </> (dropExtension (fileRefPath input) <> suffix)
        , fileRefRole = GeneratedSource
        , fileRefLanguage = Just language
        , fileRefOwner = Just (targetRecipeName target)
        }
    OutputCustom role suffix ->
      FileRef
        { fileRefPath =
            targetInterDir context (targetRecipeName target)
              </> "custom"
              </> (dropExtension (fileRefPath input) <> suffix)
        , fileRefRole = role
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (targetRecipeName target)
        }
    OutputTargetBinary ->
      targetRecipeOutput target

foldTransformOutput :: TargetRecipe -> TransformRule -> FileRef
foldTransformOutput target rule =
  case transformOutput rule of
    OutputTargetBinary ->
      targetRecipeOutput target
    OutputCustom role suffix ->
      FileRef
        { fileRefPath =
            fileRefPath (targetRecipeOutput target) <> suffix
        , fileRefRole = role
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (targetRecipeName target)
        }
    OutputObject ->
      targetRecipeOutput target
    OutputGeneratedSource language suffix ->
      FileRef
        { fileRefPath =
            fileRefPath (targetRecipeOutput target) <> suffix
        , fileRefRole = GeneratedSource
        , fileRefLanguage = Just language
        , fileRefOwner = Just (targetRecipeName target)
        }

targetSourceRefs :: TargetRecipe -> [DiscoveredSource] -> [FileRef]
targetSourceRefs target discovered =
  map discoveredSourceFileRef $
    filter ((targetRecipeName target ==) . discoveredSourceOwner) discovered

discoveredSourceFileRef :: DiscoveredSource -> FileRef
discoveredSourceFileRef source = FileRef
  { fileRefPath =
      discoveredSourceBaseDir source </> discoveredSourcePath source
  , fileRefRole = SourceFile
  , fileRefLanguage = Just (discoveredSourceLanguage source)
  , fileRefOwner = Just (discoveredSourceOwner source)
  }

targetInterDir :: BuildContext -> TargetName -> FilePath
targetInterDir context target =
  buildInterDir (contextBuildDirs context) </> targetNameString target

targetNameString :: TargetName -> String
targetNameString (TargetName name) =
  Text.unpack name

normalizedObjectPath :: FileRef -> FilePath
normalizedObjectPath =
  joinPathWithUnderscore . splitDirectories . fileRefPath

joinPathWithUnderscore :: [FilePath] -> FilePath
joinPathWithUnderscore =
  foldr joinPart ""
  where
    joinPart part "" = part
    joinPart part rest = part <> "_" <> rest

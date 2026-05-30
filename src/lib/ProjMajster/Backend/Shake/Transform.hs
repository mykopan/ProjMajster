module ProjMajster.Backend.Shake.Transform
  ( CommandRunner
  , CommandSpec(..)
  , ShakeTransformRunner
  , TransformInstance(..)
  , TransformRunnerRegistry(..)
  , builtinCommandTransformRunners
  , defaultTransformRunnerRegistry
  , planMapTransforms
  , planTargetTransforms
  , transformInstanceRules
  , transformInstanceRulesWith
  , transformRunnerRegistry
  ) where

import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Set as Set
import Development.Shake
import System.FilePath ((</>), (<.>), dropExtension, splitDirectories, takeDirectory)
import qualified System.Directory as Directory

import ProjMajster.Backend.Shake.SourceDiscovery
import ProjMajster.Core
import ProjMajster.Recipe

type ShakeTransformRunner =
  RuleContext -> TransformRule -> [FileRef] -> [FileRef] -> Action ()

type CommandRunner =
  RuleContext -> CommandSpec -> Action ()

data CommandSpec = CommandSpec
  { commandExecutable :: FilePath
  , commandArguments :: [String]
  , commandInputs :: [FileRef]
  , commandOutputs :: [FileRef]
  } deriving (Eq, Show)

data TransformInstance = TransformInstance
  { transformInstanceTarget :: TargetName
  , transformInstanceRuleContext :: RuleContext
  , transformInstanceRule :: TransformRule
  , transformInstanceInputs :: [FileRef]
  , transformInstanceOutputs :: [FileRef]
  } deriving (Eq, Show)

data TransformRunnerRegistry = TransformRunnerRegistry
  { transformRunners :: Map.Map TransformAction ShakeTransformRunner
  , transformFallbackRunner :: ShakeTransformRunner
  }

defaultTransformRunnerRegistry :: TransformRunnerRegistry
defaultTransformRunnerRegistry = TransformRunnerRegistry
  { transformRunners = Map.empty
  , transformFallbackRunner = stampTransformRunner
  }

transformRunnerRegistry :: [(TransformAction, ShakeTransformRunner)] -> TransformRunnerRegistry
transformRunnerRegistry runners = defaultTransformRunnerRegistry
  { transformRunners = Map.fromList runners
  }

builtinCommandTransformRunners :: CommandRunner -> [(TransformAction, ShakeTransformRunner)]
builtinCommandTransformRunners commandRunner =
  [ (BuiltinAction BuiltinCompileC, compileCTransformRunner commandRunner)
  ]

compileCTransformRunner :: CommandRunner -> ShakeTransformRunner
compileCTransformRunner commandRunner context _rule inputs outputs =
  case (inputs, outputs) of
    ([input], [output]) ->
      commandRunner context CommandSpec
        { commandExecutable = "cc"
        , commandArguments = ["-c", fileRefPath input, "-o", fileRefPath output]
        , commandInputs = inputs
        , commandOutputs = outputs
        }
    _ ->
      fail "compile-c transform expects exactly one input and one output"

transformInstanceRules :: [TransformInstance] -> Rules ()
transformInstanceRules =
  transformInstanceRulesWith defaultTransformRunnerRegistry

transformInstanceRulesWith :: TransformRunnerRegistry -> [TransformInstance] -> Rules ()
transformInstanceRulesWith registry =
  mapM_ (transformInstanceBuildRules registry)

transformInstanceBuildRules :: TransformRunnerRegistry -> TransformInstance -> Rules ()
transformInstanceBuildRules registry instance_ =
  case transformInstanceOutputs instance_ of
    [] ->
      pure ()
    outputs ->
      map fileRefPath outputs &%> \_ -> do
        need (map fileRefPath (transformInstanceInputs instance_))
        runTransformInstance registry instance_

runTransformInstance :: TransformRunnerRegistry -> TransformInstance -> Action ()
runTransformInstance registry instance_ =
  runner
    (transformInstanceRuleContext instance_)
    (transformInstanceRule instance_)
    (transformInstanceInputs instance_)
    (transformInstanceOutputs instance_)
  where
    runner =
      Map.findWithDefault
        (transformFallbackRunner registry)
        (transformAction (transformInstanceRule instance_))
        (transformRunners registry)

stampTransformRunner :: ShakeTransformRunner
stampTransformRunner context rule inputs outputs =
  mapM_ writeOutput outputs
  where
    writeOutput output = do
      liftIO $ Directory.createDirectoryIfMissing True (takeDirectory (fileRefPath output))
      writeFileChanged (fileRefPath output) (transformInstanceStamp context rule inputs output)

transformInstanceStamp :: RuleContext -> TransformRule -> [FileRef] -> FileRef -> String
transformInstanceStamp context rule inputs output = unlines $
  [ "transform: " <> transformNameString (transformName rule)
  , "target: " <> targetNameString (ruleContextTargetName context)
  , "output: " <> fileRefPath output
  , "inputs:"
  ] <>
  [ "- " <> fileRefPath input
  | input <- inputs
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
  , transformInstanceOutputs = foldTransformOutputs target rule
  }

ruleContext :: BuildContext -> TargetRecipe -> RuleContext
ruleContext context target = RuleContext
  { ruleContextTargetName = targetRecipeName target
  , ruleContextTargetKind = targetRecipeKind target
  , ruleContextTargetProductBase = targetRecipeProductBase target
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
    OutputTargetProducts [] ->
      targetRecipeProductBase target
    OutputTargetProducts (productMapping : _) ->
      productOutput target productMapping

foldTransformOutputs :: TargetRecipe -> TransformRule -> [FileRef]
foldTransformOutputs target rule =
  case transformOutput rule of
    OutputTargetProducts [] ->
      [targetRecipeProductBase target]
    OutputTargetProducts products ->
      map (productOutput target) products
    OutputCustom role suffix ->
      [targetRelativeOutput target role suffix Nothing]
    OutputObject ->
      [targetRecipeProductBase target]
    OutputGeneratedSource language suffix ->
      [targetRelativeOutput target GeneratedSource suffix (Just language)]

productOutput :: TargetRecipe -> ProductMapping -> FileRef
productOutput target productMapping =
  targetRelativeOutput target (productRole productMapping) (productSuffix productMapping) Nothing

targetRelativeOutput :: TargetRecipe -> FileRole -> FilePath -> Maybe Language -> FileRef
targetRelativeOutput target role suffix language = FileRef
  { fileRefPath =
      fileRefPath (targetRecipeProductBase target) <> suffix
  , fileRefRole = role
  , fileRefLanguage = language
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

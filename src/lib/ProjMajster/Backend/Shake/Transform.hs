module ProjMajster.Backend.Shake.Transform
  ( CommandRunner
  , CommandSpec(..)
  , ShakeTransformRunner
  , TransformManifest(..)
  , TransformInstance(..)
  , TransformRunnerRegistry(..)
  , builtinCommandTransformRunners
  , defaultTransformRunnerRegistry
  , parseTransformManifestContent
  , planMapTransforms
  , planTargetTransforms
  , readTransformManifest
  , targetBuildRules
  , targetBuildStampPath
  , transformManifest
  , transformManifestIndex
  , transformManifestPath
  , transformManifestProducts
  , transformManifestRules
  , transformOutputRulesWith
  , transformRunnerRegistry
  , writeTransformManifest
  ) where

import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import qualified Data.Set as Set
import Development.Shake
import System.FilePath ((</>), (<.>), dropExtension, splitDirectories, takeDirectory)
import qualified System.Directory as Directory
import Text.Read (readMaybe)

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
  } deriving (Eq, Show, Read)

newtype TransformManifest = TransformManifest
  { transformManifestInstances :: [TransformInstance]
  } deriving (Eq, Show, Read)

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

transformManifest :: [TransformInstance] -> TransformManifest
transformManifest =
  TransformManifest

transformManifestPath :: BuildContext -> TargetRecipe -> FilePath
transformManifestPath context target =
  buildInterDir (contextBuildDirs context)
    </> "targets"
    </> targetNameString (targetRecipeName target)
    </> "transforms.manifest"

writeTransformManifest :: FilePath -> TransformManifest -> Action ()
writeTransformManifest path manifest = do
  liftIO $ Directory.createDirectoryIfMissing True (takeDirectory path)
  writeFileChanged path (encodeTransformManifest manifest)

readTransformManifest :: FilePath -> Action TransformManifest
readTransformManifest path =
  parseTransformManifestContent <$> readFile' path

parseTransformManifestContent :: String -> TransformManifest
parseTransformManifestContent =
  TransformManifest . mapMaybe readMaybe . filter (not . null) . lines

transformManifestIndex :: TransformManifest -> Map.Map FilePath TransformInstance
transformManifestIndex manifest =
  Map.fromList
    [ (fileRefPath output, instance_)
    | instance_ <- transformManifestInstances manifest
    , output <- transformInstanceOutputs instance_
    ]

transformManifestProducts :: TransformManifest -> [FileRef]
transformManifestProducts manifest =
  [ output
  | instance_ <- transformManifestInstances manifest
  , transformKind (transformInstanceRule instance_) == FoldTransform
  , output <- transformInstanceOutputs instance_
  ]

transformManifestRules :: BuildContext -> BuildRecipe -> Rules ()
transformManifestRules context recipe =
  mapM_ targetTransformManifestRule (recipeTargets recipe)
  where
    manifests = sourceManifests context recipe

    targetTransformManifestRule target =
      transformManifestPath context target %> \output -> do
        let targetSourceManifests =
              filter ((targetRecipeName target ==) . sourceDiscoveryOwner . sourceManifestDiscovery) manifests
        need (map sourceManifestPath targetSourceManifests)
        discovered <- concat <$> mapM readSourceManifest targetSourceManifests
        let instances = planTargetTransforms context target discovered []
        writeTransformManifest output (transformManifest instances)

transformOutputRulesWith :: BuildContext -> BuildRecipe -> TransformRunnerRegistry -> Rules ()
transformOutputRulesWith context recipe registry = do
  loadIndex <- newCache $ \manifestPath -> do
    transformManifestIndex <$> readTransformManifest manifestPath
  let manifestPaths =
        map (transformManifestPath context) (recipeTargets recipe)
  mapM_ (targetIntermediateRules loadIndex manifestPaths) (recipeTargets recipe)
  recursivePattern (buildProductDir (contextBuildDirs context)) %>
    buildPlannedOutput loadIndex manifestPaths
  where
    buildPlannedOutput loadIndex manifestPaths outputPath = do
      need manifestPaths
      indexes <- mapM loadIndex manifestPaths
      case lookupTransformInstance outputPath indexes of
        Nothing ->
          fail $ "no transform instance produces output: " <> outputPath
        Just instance_ -> do
          need (map fileRefPath (transformInstanceInputs instance_))
          runTransformInstance registry instance_

    targetIntermediateRules loadIndex manifestPaths target = do
      let interDir = targetInterDir context (targetRecipeName target)
      recursivePattern (interDir </> "obj") %>
        buildPlannedOutput loadIndex manifestPaths
      recursivePattern (interDir </> "generated") %>
        buildPlannedOutput loadIndex manifestPaths
      recursivePattern (interDir </> "custom") %>
        buildPlannedOutput loadIndex manifestPaths

    recursivePattern dir =
      dir <> "//*"

lookupTransformInstance
  :: FilePath
  -> [Map.Map FilePath TransformInstance]
  -> Maybe TransformInstance
lookupTransformInstance _ [] =
  Nothing
lookupTransformInstance outputPath (index : indexes) =
  case Map.lookup outputPath index of
    Just instance_ ->
      Just instance_
    Nothing ->
      lookupTransformInstance outputPath indexes

targetBuildRules :: BuildContext -> BuildRecipe -> Rules ()
targetBuildRules context recipe =
  mapM_ targetBuildRule (recipeTargets recipe)
  where
    targetBuildRule target =
      targetBuildStampPath context target %> \output -> do
        let manifestPath = transformManifestPath context target
        need [manifestPath]
        manifest <- readTransformManifest manifestPath
        let products = transformManifestProducts manifest
        need (map fileRefPath products)
        writeFileChanged output (targetBuildStamp target products)

targetBuildStampPath :: BuildContext -> TargetRecipe -> FilePath
targetBuildStampPath context target =
  buildInterDir (contextBuildDirs context)
    </> "targets"
    </> targetNameString (targetRecipeName target)
    </> "target.done"

targetBuildStamp :: TargetRecipe -> [FileRef] -> String
targetBuildStamp target products = unlines $
  [ "target: " <> targetNameString (targetRecipeName target)
  , "products:"
  ] <>
  [ "- " <> fileRefPath productFile
  | productFile <- products
  ]

encodeTransformManifest :: TransformManifest -> String
encodeTransformManifest manifest =
  unlines (map show (transformManifestInstances manifest))

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
  , ruleContextTargetProductDir = targetRecipeProductDir target
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
    OutputDefaultTargetProducts _ ->
      error "OutputDefaultTargetProducts must be resolved before transform planning"
    OutputTargetProducts [] ->
      error "OutputTargetProducts requires at least one product"
    OutputTargetProducts (productMapping : _) ->
      productOutput target productMapping

foldTransformOutputs :: TargetRecipe -> TransformRule -> [FileRef]
foldTransformOutputs target rule =
  case transformOutput rule of
    OutputTargetProducts [] ->
      []
    OutputTargetProducts products ->
      map (productOutput target) products
    OutputDefaultTargetProducts _ ->
      []
    OutputCustom role suffix ->
      [targetRelativeOutput target role suffix Nothing]
    OutputObject ->
      [targetRelativeOutput target ObjectFile "output.o" Nothing]
    OutputGeneratedSource language suffix ->
      [targetRelativeOutput target GeneratedSource suffix (Just language)]

productOutput :: TargetRecipe -> ProductMapping -> FileRef
productOutput target productMapping = FileRef
  { fileRefPath = productPath productMapping
  , fileRefRole = productRole productMapping
  , fileRefLanguage = Nothing
  , fileRefOwner = Just (targetRecipeName target)
  }

targetRelativeOutput :: TargetRecipe -> FileRole -> FilePath -> Maybe Language -> FileRef
targetRelativeOutput target role suffix language = FileRef
  { fileRefPath =
      targetRecipeProductDir target </> suffix
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

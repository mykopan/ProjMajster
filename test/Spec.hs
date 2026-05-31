{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (catch)
import Control.Monad (unless)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Development.Shake
import Development.Shake.FilePath
import qualified System.Directory as Directory

import ProjMajster

main :: IO ()
main = do
  testDslBuildsProject
  testPlanningResolvesProject
  testRecipeBuildsTransformPipelines
  testShakeSourceDiscovery
  testMapTransformPlanning
  testShakeTransformInstanceRules
  testShakeTransformOutputRules
  testDuplicateTargetsFail
  testUnknownBuildStyleFails

testDslBuildsProject :: IO ()
testDslBuildsProject = do
  assertEqual "project name"
    (ProjectName "Demo")
    (projectName demoProject)

  assertEqual "project version"
    [0, 1, 0]
    (projectVersion demoProject)

  assertEqual "target count"
    2
    (length (projectTargets demoProject))

  assertEqual "build style count"
    2
    (Map.size (projectBuildStyleSettings demoProject))

  (lib, app) <- case projectTargets demoProject of
    [libTarget, appTarget] -> pure (libTarget, appTarget)
    targets -> fail $
      "expected exactly two targets, got " <> show (length targets)

  assertEqual "shared library name"
    (TargetName "foo")
    (targetName lib)

  assertEqual "shared library kind"
    (SharedLibrary NormalSharedLibrary)
    (targetKind lib)

  assertEqual "shared library link mode"
    (Just LinkShared)
    (linkSettingsMode (linkSettings (targetSettings lib)))

  assertEqual "shared library source language"
    [C, Cxx, CustomLanguage "json"]
    [ sourcePatternLanguage pattern
    | sourceSet <- targetSourceSets lib
    , pattern <- sourceSetPatterns sourceSet
    ]

  assertEqual "shared library link libraries"
    [LibraryName "m"]
    (linkLibraries (linkSettings (targetSettings lib)))

  assertEqual "program name"
    (TargetName "app")
    (targetName app)

  assertEqual "program link mode"
    (Just LinkProgram)
    (linkSettingsMode (linkSettings (targetSettings app)))

  assertEqual "program link libraries"
    [LibraryName "foo"]
    (linkLibraries (linkSettings (targetSettings app)))

  assertEqual "external dependencies"
    [DepName "Bo"]
    (map externalDepName (projectExternalDeps demoProject))

testPlanningResolvesProject :: IO ()
testPlanningResolvesProject = do
  plan <- assertRight "resolve release project" $
    resolveProject releaseContext demoProject

  assertEqual "resolved target count"
    2
    (length (planTargets plan))

  (_, app) <- case planTargets plan of
    [libTarget, appTarget] -> pure (libTarget, appTarget)
    targets -> fail $
      "expected exactly two resolved targets, got " <> show (length targets)

  assertEqual "app internal deps inferred from usesLibs"
    [InternalDependency (InternalDep (TargetName "foo"))]
    (resolvedTargetDeps app)

  assertEqual "release optimization merged into app"
    (Just Optimize)
    (commonOptimization
      (commonSettings (resolvedTargetSettings app)))

  assertEqual "project warnings merged into app"
    (Just AllWarnings)
    (commonWarningPolicy
      (commonSettings (resolvedTargetSettings app)))

  debugPlan <- assertRight "resolve debug project" $
    resolveProject debugContext demoProject

  (_, debugApp) <- case planTargets debugPlan of
    [libTarget, appTarget] -> pure (libTarget, appTarget)
    targets -> fail $
      "expected exactly two resolved targets, got " <> show (length targets)

  assertEqual "debug optimization merged into app"
    (Just NoOptimization)
    (commonOptimization
      (commonSettings (resolvedTargetSettings debugApp)))

  assertEqual "debug info merged into app"
    (Just FullDebugInfo)
    (commonDebugInfo
      (commonSettings (resolvedTargetSettings debugApp)))

  assertEqual "build style does not change dependencies"
    (resolvedTargetDeps app)
    (resolvedTargetDeps debugApp)

testRecipeBuildsTransformPipelines :: IO ()
testRecipeBuildsTransformPipelines = do
  plan <- assertRight "resolve release project" $
    resolveProject releaseContext demoProject

  let graph = lowerBuildPlan plan

  assertEqual "source discovery count"
    4
    (length (recipeSources graph))

  (libBuild, appBuild) <- case recipeTargets graph of
    [libTarget, appTarget] -> pure (libTarget, appTarget)
    targets -> fail $
      "expected exactly two target recipes, got " <> show (length targets)

  assertEqual "library transform pipeline"
    [ CustomAction "json-to-c"
    , BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinCompileCxx
    , BuiltinAction BuiltinLink
    ]
    (map transformAction (targetRecipeTransforms libBuild))

  assertEqual "app transform pipeline"
    [ BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinCompileCxx
    , BuiltinAction BuiltinLink
    ]
    (map transformAction (targetRecipeTransforms appBuild))

  assertEqual "app target recipe depends on library target"
    [TargetName "foo"]
    (targetRecipeDependencies appBuild)

  assertEqual "library output role"
    SharedObject
    (fileRefRole (targetRecipeProductBase libBuild))

  assertEqual "app output role"
    ProgramBinary
    (fileRefRole (targetRecipeProductBase appBuild))

  assertEqual "json transform stays in graph as rule"
    [OutputGeneratedSource C ".c"]
    [ transformOutput rule
    | rule <- targetRecipeTransforms libBuild
    , transformAction rule == CustomAction "json-to-c"
    ]

testShakeSourceDiscovery :: IO ()
testShakeSourceDiscovery = do
  let root = "test" </> "tmp" </> "source-discovery"
  Directory.removePathForcibly root `catchIO` \_ -> pure ()
  Directory.createDirectoryIfMissing True (root </> "src" </> "foo")
  writeFile (root </> "src" </> "foo" </> "a.c") ""
  writeFile (root </> "src" </> "foo" </> "b.c") ""
  writeFile (root </> "src" </> "foo" </> "ignored.txt") ""

  let context = releaseContext
        { contextBuildDirs = BuildDirs
            { buildRootDir = root </> "_build"
            , buildInterDir = root </> "_build" </> "inter"
            , buildProductDir = root </> "_build" </> "product"
            , buildDistDir = root </> "_build" </> "dist"
            }
        }
  let graph = BuildRecipe
        { recipeSources =
            [ SourceDiscovery
                { sourceDiscoveryOwner = TargetName "foo"
                , sourceDiscoveryPattern = SourcePattern
                    { sourcePatternBaseDir = root </> "src" </> "foo"
                    , sourcePatternGlob = "*.c"
                    , sourcePatternLanguage = C
                    }
                }
            ]
        , recipeTargets = []
        }

  let manifests = sourceManifests context graph

  shake shakeOptions
    { shakeFiles = root </> "_shake"
    , shakeVerbosity = Silent
    } $ do
      sourceDiscoveryRules context graph
      want (map sourceManifestPath manifests)

  manifest <- case manifests of
    [single] -> pure single
    xs -> fail $ "expected one manifest, got " <> show (length xs)

  discovered <- parseSourceManifestContent <$>
    readFile (sourceManifestPath manifest)

  assertEqual "shake discovered sources"
    [ DiscoveredSource
        { discoveredSourceOwner = TargetName "foo"
        , discoveredSourceBaseDir = root </> "src" </> "foo"
        , discoveredSourcePath = "a.c"
        , discoveredSourceLanguage = C
        }
    , DiscoveredSource
        { discoveredSourceOwner = TargetName "foo"
        , discoveredSourceBaseDir = root </> "src" </> "foo"
        , discoveredSourcePath = "b.c"
        , discoveredSourceLanguage = C
        }
    ]
    discovered

testMapTransformPlanning :: IO ()
testMapTransformPlanning = do
  plan <- assertRight "resolve release project" $
    resolveProject releaseContext demoProject
  let graph = lowerBuildPlan plan

  libBuild <- case recipeTargets graph of
    libTarget : _ -> pure libTarget
    [] -> fail "expected at least one target recipe"
  let reorderedLibBuild = libBuild
        { targetRecipeTransforms =
            reorderForClosureTest (targetRecipeTransforms libBuild)
        }
  let dependencyOutput = FileRef
        { fileRefPath = "_build/product/libdep.so"
        , fileRefRole = SharedObject
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (TargetName "dep")
        }

  let discovered =
        [ DiscoveredSource
            { discoveredSourceOwner = TargetName "foo"
            , discoveredSourceBaseDir = "src/foo"
            , discoveredSourcePath = "config.json"
            , discoveredSourceLanguage = CustomLanguage "json"
            }
        , DiscoveredSource
            { discoveredSourceOwner = TargetName "foo"
            , discoveredSourceBaseDir = "src/foo"
            , discoveredSourcePath = "main.c"
            , discoveredSourceLanguage = C
            }
        , DiscoveredSource
            { discoveredSourceOwner = TargetName "foo"
            , discoveredSourceBaseDir = "src/foo"
            , discoveredSourcePath = "main.cpp"
            , discoveredSourceLanguage = Cxx
            }
        ]

  let instances =
        planTargetTransforms releaseContext reorderedLibBuild discovered [dependencyOutput]

  assertEqual "target transform action counts"
    [ (BuiltinAction BuiltinCompileC, 2)
    , (BuiltinAction BuiltinCompileCxx, 1)
    , (BuiltinAction BuiltinLink, 1)
    , (CustomAction "json-to-c", 1)
    ]
    (actionCounts instances)

  assertEqual "target transform output roles"
    (sort [GeneratedSource, ObjectFile, ObjectFile, ObjectFile, SharedObject])
    (sort
      [ role
      | instance_ <- instances
      , output <- transformInstanceOutputs instance_
      , let role = fileRefRole output
      ])

  linkRule <- case
      [ rule
      | rule <- targetRecipeTransforms reorderedLibBuild
      , transformAction rule == BuiltinAction BuiltinLink
      ] of
    [rule] -> pure rule
    xs -> fail $ "expected one link rule, got " <> show (length xs)
  let multiProductLink = linkRule
        { transformOutput = OutputTargetProducts
            [ ProductMapping SharedObject ""
            , ProductMapping ImportLibrary ".lib"
            , ProductMapping Manifest ".manifest"
            ]
        }
  let multiProductTarget = reorderedLibBuild
        { targetRecipeTransforms =
            multiProductLink :
              filter ((BuiltinAction BuiltinLink /=) . transformAction)
                (targetRecipeTransforms reorderedLibBuild)
        }
  let multiProductInstances =
        planTargetTransforms releaseContext multiProductTarget discovered [dependencyOutput]

  assertEqual "fold transform can produce multiple target products"
    (sort [ImportLibrary, Manifest, SharedObject])
    (sort
      [ fileRefRole output
      | instance_ <- multiProductInstances
      , transformAction (transformInstanceRule instance_) == BuiltinAction BuiltinLink
      , output <- transformInstanceOutputs instance_
      ])

  assertEqual "transform rule context target"
    [TargetName "foo"]
    (unique
      [ ruleContextTargetName (transformInstanceRuleContext instance_)
      | instance_ <- instances
      ])

  assertEqual "transform rule context build style"
    [release]
    (unique
      [ ruleContextBuildStyle (transformInstanceRuleContext instance_)
      | instance_ <- instances
      ])

  assertEqual "generated c participates in compile c"
    [Just C]
    [ fileRefLanguage input
    | instance_ <- instances
    , transformAction (transformInstanceRule instance_) == BuiltinAction BuiltinCompileC
    , input <- transformInstanceInputs instance_
    , fileRefRole input == GeneratedSource
    ]

  linkInstance <- case
      [ instance_
      | instance_ <- instances
      , transformAction (transformInstanceRule instance_) == BuiltinAction BuiltinLink
      ] of
    [instance_] -> pure instance_
    xs -> fail $ "expected one link instance, got " <> show (length xs)

  assertEqual "link inputs include objects and dependency output"
    [ObjectFile, ObjectFile, ObjectFile, SharedObject]
    (sort (map fileRefRole (transformInstanceInputs linkInstance)))

  let manifest = transformManifest instances
  assertEqual "transform manifest roundtrip"
    manifest
    (parseTransformManifestContent
      (unlines (map show (transformManifestInstances manifest))))

  assertEqual "transform manifest products"
    [SharedObject]
    (map fileRefRole (transformManifestProducts manifest))

  assertEqual "transform manifest indexes link output"
    (Just (BuiltinAction BuiltinLink))
    (transformAction . transformInstanceRule <$>
      Map.lookup
        (fileRefPath (head (transformInstanceOutputs linkInstance)))
        (transformManifestIndex manifest))

reorderForClosureTest :: [TransformRule] -> [TransformRule]
reorderForClosureTest rules =
  filter ((BuiltinAction BuiltinLink ==) . transformAction) rules <>
  filter ((BuiltinAction BuiltinCompileC ==) . transformAction) rules <>
  filter ((CustomAction "json-to-c" ==) . transformAction) rules <>
  filter ((BuiltinAction BuiltinCompileC /=) . transformAction)
    (filter ((CustomAction "json-to-c" /=) . transformAction)
      (filter ((BuiltinAction BuiltinLink /=) . transformAction) rules))

actionCounts :: [TransformInstance] -> [(TransformAction, Int)]
actionCounts instances =
  [ (transformAction', countAction transformAction' instances)
  | transformAction' <-
      [ BuiltinAction BuiltinCompileC
      , BuiltinAction BuiltinCompileCxx
      , BuiltinAction BuiltinLink
      , CustomAction "json-to-c"
      ]
  ]

countAction :: TransformAction -> [TransformInstance] -> Int
countAction transformAction' instances =
  length
    [ ()
    | instance_ <- instances
    , transformAction (transformInstanceRule instance_) == transformAction'
    ]

unique :: Ord a => [a] -> [a]
unique =
  Set.toList . Set.fromList

testShakeTransformInstanceRules :: IO ()
testShakeTransformInstanceRules = do
  let root = "test" </> "tmp" </> "transform-rules"
  Directory.removePathForcibly root `catchIO` \_ -> pure ()
  Directory.createDirectoryIfMissing True (root </> "src" </> "foo")
  Directory.createDirectoryIfMissing True (root </> "_build" </> "product")
  writeFile (root </> "src" </> "foo" </> "config.json") "{}"
  writeFile (root </> "src" </> "foo" </> "main.c") "int main_c;"
  writeFile (root </> "src" </> "foo" </> "main.cpp") "int main_cpp;"
  writeFile (root </> "_build" </> "product" </> "libdep.so") "dep"

  plan <- assertRight "resolve release project" $
    resolveProject releaseContext demoProject
  let graph = lowerBuildPlan plan

  libBuild0 <- case recipeTargets graph of
    libTarget : _ -> pure libTarget
    [] -> fail "expected at least one target recipe"

  let context = releaseContext
        { contextBuildDirs = BuildDirs
            { buildRootDir = root </> "_build"
            , buildInterDir = root </> "_build" </> "inter"
            , buildProductDir = root </> "_build" </> "product"
            , buildDistDir = root </> "_build" </> "dist"
            }
        }
  let sourceDiscoveries =
        [ SourceDiscovery
            { sourceDiscoveryOwner = TargetName "foo"
            , sourceDiscoveryPattern = SourcePattern
                { sourcePatternBaseDir = root </> "src" </> "foo"
                , sourcePatternGlob = "**/*.json"
                , sourcePatternLanguage = CustomLanguage "json"
                }
            }
        , SourceDiscovery
            { sourceDiscoveryOwner = TargetName "foo"
            , sourceDiscoveryPattern = SourcePattern
                { sourcePatternBaseDir = root </> "src" </> "foo"
                , sourcePatternGlob = "**/*.c"
                , sourcePatternLanguage = C
                }
            }
        , SourceDiscovery
            { sourceDiscoveryOwner = TargetName "foo"
            , sourceDiscoveryPattern = SourcePattern
                { sourcePatternBaseDir = root </> "src" </> "foo"
                , sourcePatternGlob = "**/*.cpp"
                , sourcePatternLanguage = Cxx
                }
            }
        ]
  let libBuild = libBuild0
        { targetRecipeTransforms =
            reorderForClosureTest (targetRecipeTransforms libBuild0)
        , targetRecipeSources = sourceDiscoveries
        , targetRecipeProductBase = FileRef
            { fileRefPath = root </> "_build" </> "product" </> "libfoo.so"
            , fileRefRole = SharedObject
            , fileRefLanguage = Nothing
            , fileRefOwner = Just (TargetName "foo")
            }
        }
  let dependencyOutput = FileRef
        { fileRefPath = root </> "_build" </> "product" </> "libdep.so"
        , fileRefRole = SharedObject
        , fileRefLanguage = Nothing
        , fileRefOwner = Just (TargetName "dep")
        }
  let discovered =
        [ DiscoveredSource
            { discoveredSourceOwner = TargetName "foo"
            , discoveredSourceBaseDir = root </> "src" </> "foo"
            , discoveredSourcePath = "config.json"
            , discoveredSourceLanguage = CustomLanguage "json"
            }
        , DiscoveredSource
            { discoveredSourceOwner = TargetName "foo"
            , discoveredSourceBaseDir = root </> "src" </> "foo"
            , discoveredSourcePath = "main.c"
            , discoveredSourceLanguage = C
            }
        , DiscoveredSource
            { discoveredSourceOwner = TargetName "foo"
            , discoveredSourceBaseDir = root </> "src" </> "foo"
            , discoveredSourcePath = "main.cpp"
            , discoveredSourceLanguage = Cxx
            }
        ]

  let instances =
        planTargetTransforms context libBuild discovered [dependencyOutput]
  let registry =
        transformRunnerRegistry
          ( builtinCommandTransformRunners recordingCommandRunner <>
            [(CustomAction "json-to-c", contextStampRunner)]
          )
  let recipe = BuildRecipe
        { recipeSources = targetRecipeSources libBuild
        , recipeTargets = [libBuild]
        }

  shake shakeOptions
    { shakeFiles = root </> "_shake"
    , shakeVerbosity = Silent
    } $ do
      sourceDiscoveryRules context recipe
      transformManifestRules context recipe
      transformInstanceRulesWith registry instances
      want
        [ transformManifestPath context libBuild
        , fileRefPath (targetRecipeProductBase libBuild)
        ]

  linkStamp <- readFile (fileRefPath (targetRecipeProductBase libBuild))
  let linkInputs = drop 4 (lines linkStamp)

  assertEqual "link stamp input count"
    4
    (length linkInputs)

  assertBool "link stamp includes dependency output" $
    ("- " <> fileRefPath dependencyOutput) `elem` linkInputs

  plannedManifest <- parseTransformManifestContent <$>
    readFile (transformManifestPath context libBuild)
  assertEqual "transform manifest rule plans products"
    [SharedObject]
    (map fileRefRole (transformManifestProducts plannedManifest))

  generatedSource <- case
      [ output
      | instance_ <- instances
      , transformAction (transformInstanceRule instance_) == CustomAction "json-to-c"
      , output <- transformInstanceOutputs instance_
      ] of
    [output] -> pure output
    xs -> fail $ "expected one generated source, got " <> show (length xs)

  generatedContent <- readFile (fileRefPath generatedSource)
  assertBool "custom runner receives rule context target" $
    "target: foo" `elem` lines generatedContent
  assertBool "custom runner receives rule context build style" $
    "style: release" `elem` lines generatedContent

  let cSource = root </> "src" </> "foo" </> "main.c"
  cObject <- case
      [ output
      | instance_ <- instances
      , transformAction (transformInstanceRule instance_) == BuiltinAction BuiltinCompileC
      , input <- transformInstanceInputs instance_
      , fileRefPath input == cSource
      , output <- transformInstanceOutputs instance_
      ] of
    [output] -> pure output
    xs -> fail $ "expected one C object output, got " <> show (length xs)

  cObjectContent <- readFile (fileRefPath cObject)
  assertEqual "compile-c command executable"
    "executable: cc"
    (head (lines cObjectContent))
  assertBool "compile-c command includes input and output arguments" $
    ("arguments: -c " <> cSource <> " -o " <> fileRefPath cObject)
      `elem` lines cObjectContent

testShakeTransformOutputRules :: IO ()
testShakeTransformOutputRules = do
  let root = "test" </> "tmp" </> "transform-output-rules"
  Directory.removePathForcibly root `catchIO` \_ -> pure ()
  Directory.createDirectoryIfMissing True (root </> "src" </> "foo")
  writeFile (root </> "src" </> "foo" </> "config.json") "{}"
  writeFile (root </> "src" </> "foo" </> "main.c") "int main_c;"

  plan <- assertRight "resolve release project" $
    resolveProject releaseContext demoProject
  graph <- pure (lowerBuildPlan plan)

  libBuild0 <- case recipeTargets graph of
    libTarget : _ -> pure libTarget
    [] -> fail "expected at least one target recipe"

  let context = releaseContext
        { contextBuildDirs = BuildDirs
            { buildRootDir = root </> "_build"
            , buildInterDir = root </> "_build" </> "inter"
            , buildProductDir = root </> "_build" </> "product"
            , buildDistDir = root </> "_build" </> "dist"
            }
        }
  let sourceDiscoveries =
        [ SourceDiscovery
            { sourceDiscoveryOwner = TargetName "foo"
            , sourceDiscoveryPattern = SourcePattern
                { sourcePatternBaseDir = root </> "src" </> "foo"
                , sourcePatternGlob = "**/*.json"
                , sourcePatternLanguage = CustomLanguage "json"
                }
            }
        , SourceDiscovery
            { sourceDiscoveryOwner = TargetName "foo"
            , sourceDiscoveryPattern = SourcePattern
                { sourcePatternBaseDir = root </> "src" </> "foo"
                , sourcePatternGlob = "**/*.c"
                , sourcePatternLanguage = C
                }
            }
        ]
  let libBuild = libBuild0
        { targetRecipeTransforms =
            reorderForClosureTest (targetRecipeTransforms libBuild0)
        , targetRecipeSources = sourceDiscoveries
        , targetRecipeProductBase = FileRef
            { fileRefPath = root </> "_build" </> "product" </> "libfoo.so"
            , fileRefRole = SharedObject
            , fileRefLanguage = Nothing
            , fileRefOwner = Just (TargetName "foo")
            }
        }
  let recipe = BuildRecipe
        { recipeSources = targetRecipeSources libBuild
        , recipeTargets = [libBuild]
        }
  let registry =
        transformRunnerRegistry
          ( builtinCommandTransformRunners recordingCommandRunner <>
            [(CustomAction "json-to-c", contextStampRunner)]
          )

  shake shakeOptions
    { shakeFiles = root </> "_shake"
    , shakeVerbosity = Silent
    } $ do
      sourceDiscoveryRules context recipe
      transformManifestRules context recipe
      transformOutputRulesWith context recipe registry
      targetBuildRules context recipe
      want [targetBuildStampPath context libBuild]

  linkStamp <- readFile (fileRefPath (targetRecipeProductBase libBuild))
  assertEqual "generic output rules build link inputs"
    2
    (length (drop 4 (lines linkStamp)))
  targetStamp <- readFile (targetBuildStampPath context libBuild)
  assertBool "target stamp records dynamic product"
    (("- " <> fileRefPath (targetRecipeProductBase libBuild)) `elem` lines targetStamp)

contextStampRunner :: ShakeTransformRunner
contextStampRunner context rule inputs outputs =
  mapM_ writeOutput outputs
  where
    writeOutput output = do
      liftIO $ Directory.createDirectoryIfMissing True (takeDirectory (fileRefPath output))
      writeFileChanged (fileRefPath output) $ unlines
        [ "transform: " <> transformNameTextString (transformName rule)
        , "target: " <> targetNameTextString (ruleContextTargetName context)
        , "style: " <> buildStyleTextString (ruleContextBuildStyle context)
        , "inputs: " <> show (length inputs)
        ]

recordingCommandRunner :: CommandRunner
recordingCommandRunner context commandSpec =
  mapM_ writeOutput (commandOutputs commandSpec)
  where
    writeOutput output = do
      liftIO $ Directory.createDirectoryIfMissing True (takeDirectory (fileRefPath output))
      writeFileChanged (fileRefPath output) $ unlines
        [ "executable: " <> commandExecutable commandSpec
        , "arguments: " <> unwords (commandArguments commandSpec)
        , "target: " <> targetNameTextString (ruleContextTargetName context)
        , "style: " <> buildStyleTextString (ruleContextBuildStyle context)
        , "inputs: " <> show (length (commandInputs commandSpec))
        , "outputs: " <> show (length (commandOutputs commandSpec))
        ]

transformNameTextString :: TransformName -> String
transformNameTextString (TransformName name) =
  Text.unpack name

targetNameTextString :: TargetName -> String
targetNameTextString (TargetName name) =
  Text.unpack name

buildStyleTextString :: BuildStyle -> String
buildStyleTextString (BuildStyle name) =
  Text.unpack name

testDuplicateTargetsFail :: IO ()
testDuplicateTargetsFail =
  assertEqual "duplicate target error"
    (Left (DuplicateTargetName (TargetName "dup")))
    (resolveProject releaseContext duplicateTargetsProject)

testUnknownBuildStyleFails :: IO ()
testUnknownBuildStyleFails =
  assertEqual "unknown build style error"
    (Left (UnknownBuildStyle (BuildStyle "asan")))
    (resolveProject releaseContext{contextBuildStyle = BuildStyle "asan"} demoProject)

demoProject :: Project
demoProject = project "Demo" $ do
  version [0, 1, 0]

  settings $ do
    warningPolicy AllWarnings

  buildStyle release $ do
    optimization Optimize

  buildStyle debug $ do
    optimization NoOptimization
    debugInfo FullDebugInfo

  binaryDep "Bo"

  sharedLibrary "foo" $ do
    sources "src/foo" $ do
      c "**/*.c"
      cxx "**/*.cpp"
      customSource "json" "**/*.json"
    transform testJsonToC
    includeDirs ["src/foo/include"]
    usesLibs ["m"]
    install RuntimeLibDir

  program "app" $ do
    sources "src/app" $ do
      c "**/*.c"
    usesLibs ["foo"]
    install BinDir

duplicateTargetsProject :: Project
duplicateTargetsProject = project "DuplicateTargets" $ do
  program "dup" $ pure ()
  sharedLibrary "dup" $ pure ()

releaseContext :: BuildContext
releaseContext = BuildContext
  { buildPlatform = linuxX86_64
  , targetPlatform = linuxX86_64
  , contextBuildStyle = release
  , contextBuildDirs = BuildDirs
      { buildRootDir = "_build/linux-x86_64/release"
      , buildInterDir = "_build/linux-x86_64/release/inter"
      , buildProductDir = "_build/linux-x86_64/release/product"
      , buildDistDir = "_build/linux-x86_64/release/dist"
      }
  }

debugContext :: BuildContext
debugContext = releaseContext
  { contextBuildStyle = debug
  }

linuxX86_64 :: Platform
linuxX86_64 = Platform
  { platformOS = Linux
  , platformArch = X86_64
  , platformAspects = []
  }

testJsonToC :: TransformRule
testJsonToC = TransformRule
  { transformName = TransformName "json-to-c"
  , transformKind = MapTransform
  , transformInput = InputLanguage (CustomLanguage "json")
  , transformOutput = OutputGeneratedSource C ".c"
  , transformAction = CustomAction "json-to-c"
  }

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  unless (expected == actual) $
    fail $ unlines
      [ label
      , "expected: " <> show expected
      , "actual:   " <> show actual
      ]

assertBool :: String -> Bool -> IO ()
assertBool label condition =
  unless condition (fail label)

assertRight :: Show e => String -> Either e a -> IO a
assertRight _ (Right value) = pure value
assertRight label (Left err) =
  fail $ label <> ": expected Right, got Left " <> show err

catchIO :: IO a -> (IOError -> IO a) -> IO a
catchIO = catch

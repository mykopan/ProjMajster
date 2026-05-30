{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import qualified Data.Map.Strict as Map

import ProjMajster

main :: IO ()
main = do
  testDslBuildsProject
  testPlanningResolvesProject
  testGraphBuildsCompileAndLinkSteps
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

testGraphBuildsCompileAndLinkSteps :: IO ()
testGraphBuildsCompileAndLinkSteps = do
  plan <- assertRight "resolve release project" $
    resolveProject releaseContext demoProject

  let graph = buildGraph plan

  assertEqual "source discovery count"
    4
    (length (graphSources graph))

  (libBuild, appBuild) <- case graphTargets graph of
    [libTarget, appTarget] -> pure (libTarget, appTarget)
    targets -> fail $
      "expected exactly two target builds, got " <> show (length targets)

  assertEqual "library transform pipeline"
    [ CustomAction "json-to-c"
    , BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinCompileCxx
    , BuiltinAction BuiltinLink
    ]
    (map transformAction (targetBuildTransforms libBuild))

  assertEqual "app transform pipeline"
    [ BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinCompileCxx
    , BuiltinAction BuiltinLink
    ]
    (map transformAction (targetBuildTransforms appBuild))

  assertEqual "app target build depends on library target"
    [TargetName "foo"]
    (targetBuildDependencies appBuild)

  assertEqual "library output role"
    SharedObject
    (fileRefRole (targetBuildOutput libBuild))

  assertEqual "app output role"
    ProgramBinary
    (fileRefRole (targetBuildOutput appBuild))

  assertEqual "json transform stays in graph as rule"
    [OutputGeneratedSource C ".c"]
    [ transformOutput rule
    | rule <- targetBuildTransforms libBuild
    , transformAction rule == CustomAction "json-to-c"
    ]

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

assertRight :: Show e => String -> Either e a -> IO a
assertRight _ (Right value) = pure value
assertRight label (Left err) =
  fail $ label <> ": expected Right, got Left " <> show err

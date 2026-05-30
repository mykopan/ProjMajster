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

  assertEqual "graph action sequence"
    [ CustomAction "discover-sources"
    , CustomAction "discover-sources"
    , CustomAction "discover-sources"
    , CustomAction "discover-sources"
    , CustomAction "json-to-c"
    , BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinCompileCxx
    , BuiltinAction BuiltinLink
    , BuiltinAction BuiltinCompileC
    , BuiltinAction BuiltinLink
    ]
    (map (transformAction . buildStepTransform) (graphSteps graph))

  assertEqual "graph file roles"
    [ SourceFile
    , SourceFile
    , SourceFile
    , GeneratedSource
    , ObjectFile
    , ObjectFile
    , ObjectFile
    , SharedObject
    , SourceFile
    , ObjectFile
    , ProgramBinary
    ]
    (map fileRefRole (graphFiles graph))

  assertEqual "source glob discovery count"
    4
    (length
      [ ()
      | step <- graphSteps graph
      , DiscoverSourceGlob _ <- buildStepDiscovered step
      ])

  assertEqual "makefile deps discovery count"
    4
    (length
      [ ()
      | step <- graphSteps graph
      , DiscoverMakefileDeps _ <- buildStepDiscovered step
      ])

  appLinkStep <- case
      [ step
      | step <- graphSteps graph
      , transformAction (buildStepTransform step) == BuiltinAction BuiltinLink
      , any ((Just (TargetName "app") ==) . fileRefOwner)
          (buildStepOutputs step)
      ] of
    [step] -> pure step
    steps -> fail $
      "expected exactly one app link step, got " <> show (length steps)

  assertEqual "app link inputs include internal library output"
    [ObjectFile, SharedObject]
    (map fileRefRole (buildStepInputs appLinkStep))

  assertEqual "json transform produces generated C"
    [Just C]
    [ fileRefLanguage output
    | step <- graphSteps graph
    , transformAction (buildStepTransform step) == CustomAction "json-to-c"
    , output <- buildStepOutputs step
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
    transform jsonToC
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

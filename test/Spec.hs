{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import qualified Data.Map.Strict as Map

import ProjMajster

main :: IO ()
main = do
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
    [C, Cxx]
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
    includeDirs ["src/foo/include"]
    usesLibs ["m"]
    install RuntimeLibDir

  program "app" $ do
    sources "src/app" $ do
      c "**/*.c"
    usesLibs ["foo"]
    install BinDir

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  unless (expected == actual) $
    fail $ unlines
      [ label
      , "expected: " <> show expected
      , "actual:   " <> show actual
      ]

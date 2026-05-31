{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.Target
  ( TargetName(..)
  , TargetKind(..)
  , SharedLibraryStyle(..)
  , PluginStyle(..)
  , FileNamePolicy(..)
  , StubPolicy(..)
  , Target(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.Install (InstallDir, InstallSpec)
import ProjMajster.Core.Settings (BuildSettings)
import ProjMajster.Core.SourceSet (SourceSet)
import ProjMajster.Core.Transform (TransformRule)

newtype TargetName = TargetName
  { targetNameText :: Text
  } deriving (Eq, Ord, Show, Read)

data TargetKind
  = Program
  | SharedLibrary SharedLibraryStyle
  deriving (Eq, Show, Read)

data SharedLibraryStyle
  = NormalSharedLibrary
  | PluginSharedLibrary PluginStyle
  deriving (Eq, Show, Read)

data PluginStyle = PluginStyle
  { pluginFileNamePolicy :: FileNamePolicy
  , pluginInstallDir :: InstallDir
  , pluginStubPolicy :: StubPolicy
  } deriving (Eq, Show, Read)

data FileNamePolicy
  = DefaultFileNamePolicy
  | ExactFileName Text
  | PlatformFileName Text
  deriving (Eq, Ord, Show, Read)

data StubPolicy
  = DefaultStubPolicy
  | NoStub
  deriving (Eq, Ord, Show, Read)

data Target = Target
  { targetName :: TargetName
  , targetKind :: TargetKind
  , targetSourceSets :: [SourceSet]
  , targetTransforms :: [TransformRule]
  , targetSettings :: BuildSettings
  , targetInstallSpecs :: [InstallSpec]
  } deriving (Eq, Show, Read)

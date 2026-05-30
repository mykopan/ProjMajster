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

newtype TargetName = TargetName
  { targetNameText :: Text
  } deriving (Eq, Ord, Show)

data TargetKind
  = Program
  | SharedLibrary SharedLibraryStyle
  deriving (Eq, Show)

data SharedLibraryStyle
  = NormalSharedLibrary
  | PluginSharedLibrary PluginStyle
  deriving (Eq, Show)

data PluginStyle = PluginStyle
  { pluginFileNamePolicy :: FileNamePolicy
  , pluginInstallDir :: InstallDir
  , pluginStubPolicy :: StubPolicy
  } deriving (Eq, Show)

data FileNamePolicy
  = DefaultFileNamePolicy
  | ExactFileName Text
  | PlatformFileName Text
  deriving (Eq, Ord, Show)

data StubPolicy
  = DefaultStubPolicy
  | NoStub
  deriving (Eq, Ord, Show)

data Target = Target
  { targetName :: TargetName
  , targetKind :: TargetKind
  , targetSourceSets :: [SourceSet]
  , targetSettings :: BuildSettings
  , targetInstallSpecs :: [InstallSpec]
  } deriving (Eq, Show)

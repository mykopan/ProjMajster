{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module ProjMajster.DSL.Internal
  ( ProjectM(..)
  , ProjectDraft(..)
  , TargetM(..)
  , TargetDraft(..)
  , SourceSetM(..)
  , SourceSetDraft(..)
  , SettingsM(..)
  , emptyProjectDraft
  , emptyTargetDraft
  , emptySourceSetDraft
  , runProjectM
  , runTargetM
  , runSourceSetM
  , runSettingsM
  , applySettingsM
  ) where

import Control.Monad.State.Strict (State, execState)
import qualified Data.Map.Strict as Map

import ProjMajster.Core

newtype ProjectM a = ProjectM
  { unProjectM :: State ProjectDraft a
  } deriving (Functor, Applicative, Monad)

data ProjectDraft = ProjectDraft
  { projectDraftName :: ProjectName
  , projectDraftVersion :: [Int]
  , projectDraftTargets :: [Target]
  , projectDraftExternalDeps :: [ExternalDep]
  , projectDraftDefaultSettings :: BuildSettings
  , projectDraftBuildStyleSettings :: Map.Map BuildStyle BuildSettings
  } deriving (Eq, Show)

emptyProjectDraft :: ProjectName -> ProjectDraft
emptyProjectDraft name = ProjectDraft
  { projectDraftName = name
  , projectDraftVersion = []
  , projectDraftTargets = []
  , projectDraftExternalDeps = []
  , projectDraftDefaultSettings = emptyBuildSettings
  , projectDraftBuildStyleSettings = Map.empty
  }

runProjectM :: ProjectName -> ProjectM () -> ProjectDraft
runProjectM name (ProjectM action) =
  execState action (emptyProjectDraft name)

newtype TargetM a = TargetM
  { unTargetM :: State TargetDraft a
  } deriving (Functor, Applicative, Monad)

data TargetDraft = TargetDraft
  { targetDraftName :: TargetName
  , targetDraftKind :: TargetKind
  , targetDraftSourceSets :: [SourceSet]
  , targetDraftSettings :: BuildSettings
  , targetDraftInstallSpecs :: [InstallSpec]
  } deriving (Eq, Show)

emptyTargetDraft :: TargetName -> TargetKind -> TargetDraft
emptyTargetDraft name kind = TargetDraft
  { targetDraftName = name
  , targetDraftKind = kind
  , targetDraftSourceSets = []
  , targetDraftSettings = emptyBuildSettings
  , targetDraftInstallSpecs = []
  }

runTargetM :: TargetName -> TargetKind -> TargetM () -> TargetDraft
runTargetM name kind (TargetM action) =
  execState action (emptyTargetDraft name kind)

newtype SourceSetM a = SourceSetM
  { unSourceSetM :: State SourceSetDraft a
  } deriving (Functor, Applicative, Monad)

data SourceSetDraft = SourceSetDraft
  { sourceSetDraftName :: String
  , sourceSetDraftBaseDir :: FilePath
  , sourceSetDraftPatterns :: [SourcePattern]
  } deriving (Eq, Show)

emptySourceSetDraft :: FilePath -> SourceSetDraft
emptySourceSetDraft baseDir = SourceSetDraft
  { sourceSetDraftName = baseDir
  , sourceSetDraftBaseDir = baseDir
  , sourceSetDraftPatterns = []
  }

runSourceSetM :: FilePath -> SourceSetM () -> SourceSetDraft
runSourceSetM baseDir (SourceSetM action) =
  execState action (emptySourceSetDraft baseDir)

newtype SettingsM a = SettingsM
  { unSettingsM :: State BuildSettings a
  } deriving (Functor, Applicative, Monad)

runSettingsM :: SettingsM () -> BuildSettings
runSettingsM = applySettingsM emptyBuildSettings

applySettingsM :: BuildSettings -> SettingsM () -> BuildSettings
applySettingsM settings (SettingsM action) =
  execState action settings

module ProjMajster.Graph.Types
  ( BuildGraph(..)
  , SourceDiscovery(..)
  , TargetBuild(..)
  , FileRef(..)
  , StepName(..)
  , BuildStep(..)
  , Discovery(..)
  , SourceGlob(..)
  , OracleKey(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.FileRole (FileRole)
import ProjMajster.Core.SourceSet (Language)
import ProjMajster.Core.Target (TargetKind, TargetName)
import ProjMajster.Core.Transform (TransformRule)

data BuildGraph = BuildGraph
  { graphSources :: [SourceDiscovery]
  , graphTargets :: [TargetBuild]
  } deriving (Eq, Show)

data SourceDiscovery = SourceDiscovery
  { sourceDiscoveryOwner :: TargetName
  , sourceDiscoveryGlob :: SourceGlob
  } deriving (Eq, Ord, Show)

data TargetBuild = TargetBuild
  { targetBuildName :: TargetName
  , targetBuildKind :: TargetKind
  , targetBuildSources :: [SourceDiscovery]
  , targetBuildTransforms :: [TransformRule]
  , targetBuildDependencies :: [TargetName]
  , targetBuildOutput :: FileRef
  } deriving (Eq, Show)

data FileRef = FileRef
  { fileRefPath :: FilePath
  , fileRefRole :: FileRole
  , fileRefLanguage :: Maybe Language
  , fileRefOwner :: Maybe TargetName
  } deriving (Eq, Ord, Show)

newtype StepName = StepName
  { stepNameText :: Text
  } deriving (Eq, Ord, Show)

data BuildStep = BuildStep
  { buildStepName :: StepName
  , buildStepInputs :: [FileRef]
  , buildStepOutputs :: [FileRef]
  , buildStepDiscovered :: [Discovery]
  , buildStepTransform :: TransformRule
  } deriving (Eq, Show)

data Discovery
  = DiscoverSourceGlob SourceGlob
  | DiscoverMakefileDeps FilePath
  | DiscoverOracle OracleKey
  deriving (Eq, Ord, Show)

data SourceGlob = SourceGlob
  { sourceGlobBaseDir :: FilePath
  , sourceGlobPattern :: FilePath
  , sourceGlobLanguage :: Language
  } deriving (Eq, Ord, Show)

newtype OracleKey = OracleKey
  { oracleKeyText :: Text
  } deriving (Eq, Ord, Show)

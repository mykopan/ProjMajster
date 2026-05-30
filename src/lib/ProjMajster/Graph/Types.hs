module ProjMajster.Graph.Types
  ( BuildGraph(..)
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
import ProjMajster.Core.Target (TargetName)
import ProjMajster.Core.Transform (TransformRule)

data BuildGraph = BuildGraph
  { graphFiles :: [FileRef]
  , graphSteps :: [BuildStep]
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

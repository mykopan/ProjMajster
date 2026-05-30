module ProjMajster.Graph
  ( BuildGraph(..)
  , FileRef(..)
  , BuildStep(..)
  , StepName(..)
  , StepAction(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.FileRole (FileRole)
import ProjMajster.Core.Target (TargetName)

data BuildGraph = BuildGraph
  { graphFiles :: [FileRef]
  , graphSteps :: [BuildStep]
  } deriving (Eq, Show)

data FileRef = FileRef
  { fileRefPath :: FilePath
  , fileRefRole :: FileRole
  , fileRefOwner :: Maybe TargetName
  } deriving (Eq, Ord, Show)

newtype StepName = StepName
  { stepNameText :: Text
  } deriving (Eq, Ord, Show)

data BuildStep = BuildStep
  { buildStepName :: StepName
  , buildStepInputs :: [FileRef]
  , buildStepOutputs :: [FileRef]
  , buildStepAction :: StepAction
  } deriving (Eq, Show)

data StepAction
  = NoStepAction
  | NamedStepAction Text
  deriving (Eq, Ord, Show)

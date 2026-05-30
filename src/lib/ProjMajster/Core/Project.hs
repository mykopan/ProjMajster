module ProjMajster.Core.Project
  ( ProjectName(..)
  , Project(..)
  ) where

import Data.Map.Strict (Map)
import Data.Text (Text)

import ProjMajster.Core.BuildStyle (BuildStyle)
import ProjMajster.Core.Dependency (ExternalDep)
import ProjMajster.Core.Settings (BuildSettings)
import ProjMajster.Core.Target (Target)

newtype ProjectName = ProjectName
  { projectNameText :: Text
  } deriving (Eq, Ord, Show)

data Project = Project
  { projectName :: ProjectName
  , projectVersion :: [Int]
  , projectTargets :: [Target]
  , projectExternalDeps :: [ExternalDep]
  , projectDefaultSettings :: BuildSettings
  , projectBuildStyleSettings :: Map BuildStyle BuildSettings
  } deriving (Eq, Show)

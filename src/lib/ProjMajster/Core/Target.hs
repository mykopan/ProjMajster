{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.Target
  ( TargetName(..)
  , Target(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.Install (InstallSpec)
import ProjMajster.Core.Settings (BuildSettings)
import ProjMajster.Core.SourceSet (SourceSet)
import ProjMajster.Core.Transform (TransformRule)

newtype TargetName = TargetName
  { targetNameText :: Text
  } deriving (Eq, Ord, Show, Read)

data Target = Target
  { targetName :: TargetName
  , targetSourceSets :: [SourceSet]
  , targetTransforms :: [TransformRule]
  , targetSettings :: BuildSettings
  , targetInstallSpecs :: [InstallSpec]
  } deriving (Eq, Show, Read)

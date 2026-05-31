module ProjMajster.Recipe.Types
  ( BuildRecipe(..)
  , RuleContext(..)
  , SourceDiscovery(..)
  , TargetRecipe(..)
  , FileRef(..)
  ) where

import ProjMajster.Core.BuildStyle (BuildStyle)
import ProjMajster.Core.FileRole (FileRole)
import ProjMajster.Core.Platform (BuildDirs, Platform)
import ProjMajster.Core.SourceSet (Language, SourcePattern)
import ProjMajster.Core.Target (TargetName)
import ProjMajster.Core.Transform (TransformRule)

data BuildRecipe = BuildRecipe
  { recipeSources :: [SourceDiscovery]
  , recipeTargets :: [TargetRecipe]
  } deriving (Eq, Show, Read)

data SourceDiscovery = SourceDiscovery
  { sourceDiscoveryOwner :: TargetName
  , sourceDiscoveryPattern :: SourcePattern
  } deriving (Eq, Ord, Show, Read)

data TargetRecipe = TargetRecipe
  { targetRecipeName :: TargetName
  , targetRecipeSources :: [SourceDiscovery]
  , targetRecipeTransforms :: [TransformRule]
  , targetRecipeDependencies :: [TargetName]
  , targetRecipeProductDir :: FilePath
  } deriving (Eq, Show, Read)

data RuleContext = RuleContext
  { ruleContextTargetName :: TargetName
  , ruleContextTargetProductDir :: FilePath
  , ruleContextBuildPlatform :: Platform
  , ruleContextTargetPlatform :: Platform
  , ruleContextBuildStyle :: BuildStyle
  , ruleContextBuildDirs :: BuildDirs
  } deriving (Eq, Show, Read)

data FileRef = FileRef
  { fileRefPath :: FilePath
  , fileRefRole :: FileRole
  , fileRefLanguage :: Maybe Language
  , fileRefOwner :: Maybe TargetName
  } deriving (Eq, Ord, Show, Read)

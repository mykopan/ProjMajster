module ProjMajster.Recipe.Types
  ( BuildRecipe(..)
  , RuleContext(..)
  , SourceDiscovery(..)
  , TargetRecipe(..)
  , FileRef(..)
  , SourceGlob(..)
  ) where

import ProjMajster.Core.BuildStyle (BuildStyle)
import ProjMajster.Core.FileRole (FileRole)
import ProjMajster.Core.Platform (BuildDirs, Platform)
import ProjMajster.Core.SourceSet (Language)
import ProjMajster.Core.Target (TargetKind, TargetName)
import ProjMajster.Core.Transform (TransformRule)

data BuildRecipe = BuildRecipe
  { recipeSources :: [SourceDiscovery]
  , recipeTargets :: [TargetRecipe]
  } deriving (Eq, Show)

data SourceDiscovery = SourceDiscovery
  { sourceDiscoveryOwner :: TargetName
  , sourceDiscoveryGlob :: SourceGlob
  } deriving (Eq, Ord, Show)

data TargetRecipe = TargetRecipe
  { targetRecipeName :: TargetName
  , targetRecipeKind :: TargetKind
  , targetRecipeSources :: [SourceDiscovery]
  , targetRecipeTransforms :: [TransformRule]
  , targetRecipeDependencies :: [TargetName]
  , targetRecipeOutput :: FileRef
  } deriving (Eq, Show)

data RuleContext = RuleContext
  { ruleContextTargetName :: TargetName
  , ruleContextTargetKind :: TargetKind
  , ruleContextTargetOutput :: FileRef
  , ruleContextBuildPlatform :: Platform
  , ruleContextTargetPlatform :: Platform
  , ruleContextBuildStyle :: BuildStyle
  , ruleContextBuildDirs :: BuildDirs
  } deriving (Eq, Show)

data FileRef = FileRef
  { fileRefPath :: FilePath
  , fileRefRole :: FileRole
  , fileRefLanguage :: Maybe Language
  , fileRefOwner :: Maybe TargetName
  } deriving (Eq, Ord, Show)

data SourceGlob = SourceGlob
  { sourceGlobBaseDir :: FilePath
  , sourceGlobPattern :: FilePath
  , sourceGlobLanguage :: Language
  } deriving (Eq, Ord, Show)

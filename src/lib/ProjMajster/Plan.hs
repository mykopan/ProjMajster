module ProjMajster.Plan
  ( BuildPlan(..)
  , ResolvedTarget(..)
  ) where

import ProjMajster.Core

data BuildPlan = BuildPlan
  { planContext :: BuildContext
  , planTargets :: [ResolvedTarget]
  , planExternalDeps :: [ResolvedDep]
  , planInstallSpecs :: [InstallSpec]
  } deriving (Eq, Show)

data ResolvedTarget = ResolvedTarget
  { resolvedTargetName :: TargetName
  , resolvedTargetKind :: TargetKind
  , resolvedTargetSources :: [FilePath]
  , resolvedTargetSettings :: BuildSettings
  , resolvedTargetDeps :: [Dependency]
  , resolvedTargetInstallSpecs :: [InstallSpec]
  } deriving (Eq, Show)

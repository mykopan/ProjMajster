module ProjMajster.Plan.Error
  ( PlanError(..)
  ) where

import ProjMajster.Core

data PlanError
  = EmptyProjectName
  | EmptyTargetName
  | DuplicateTargetName TargetName
  | UnknownBuildStyle BuildStyle
  deriving (Eq, Show)

{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.Dependency
  ( DepName(..)
  , DepAspect(..)
  , VersionReq(..)
  , ExternalDep(..)
  , InternalDep(..)
  , Dependency(..)
  , ResolvedDep(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.Settings (LibraryName)
import ProjMajster.Core.Target (TargetName)

newtype DepName = DepName
  { depNameText :: Text
  } deriving (Eq, Ord, Show)

newtype DepAspect = DepAspect
  { depAspectText :: Text
  } deriving (Eq, Ord, Show)

data VersionReq
  = AnyVersion
  | ExactVersion [Int]
  | VersionAtLeast [Int]
  deriving (Eq, Ord, Show)

data ExternalDep = ExternalDep
  { externalDepName :: DepName
  , externalDepVersion :: VersionReq
  , externalDepAspects :: [DepAspect]
  } deriving (Eq, Show)

newtype InternalDep = InternalDep
  { internalDepTarget :: TargetName
  } deriving (Eq, Ord, Show)

data Dependency
  = ExternalDependency ExternalDep
  | InternalDependency InternalDep
  deriving (Eq, Show)

data ResolvedDep = ResolvedDep
  { resolvedDepRoot :: FilePath
  , resolvedDepIncludeDirs :: [FilePath]
  , resolvedDepLibraryDirs :: [FilePath]
  , resolvedDepRuntimeDirs :: [FilePath]
  , resolvedDepLibraries :: [LibraryName]
  } deriving (Eq, Show)

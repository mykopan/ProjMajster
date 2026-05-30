{-# LANGUAGE OverloadedStrings #-}

module ProjMajster.Core.Platform
  ( OS(..)
  , Arch(..)
  , Platform(..)
  , BuildContext(..)
  ) where

import Data.Text (Text)

import ProjMajster.Core.BuildStyle (BuildStyle)

data OS
  = Windows
  | Linux
  | MacOSX
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data Arch
  = X86
  | X86_64
  | Armv7
  | Arm64
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data Platform = Platform
  { platformOS :: OS
  , platformArch :: Arch
  , platformAspects :: [Text]
  } deriving (Eq, Ord, Show)

data BuildContext = BuildContext
  { buildPlatform :: Platform
  , targetPlatform :: Platform
  , buildStyle :: BuildStyle
  } deriving (Eq, Show)

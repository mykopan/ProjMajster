module ProjMajster.Core.Install
  ( InstallDir(..)
  , InstallSpec(..)
  ) where

import Data.Text (Text)

data InstallDir
  = BinDir
  | LibDir
  | RuntimeLibDir
  | IncludeDir
  | ShareDir FilePath
  | CustomInstallDir FilePath
  deriving (Eq, Ord, Show, Read)

data InstallSpec = InstallSpec
  { installSpecDir :: InstallDir
  , installSpecRole :: Maybe Text
  } deriving (Eq, Show, Read)
